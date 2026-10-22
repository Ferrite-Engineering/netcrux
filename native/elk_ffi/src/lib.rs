// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

//! The C ABI NetCrux's desktop layout host calls: a layout job that takes an
//! ELK JSON document and produces the laid-out ELK JSON document, reporting
//! its progress and stopping when asked, plus the allocator pair the caller
//! uses for the byte buffers on both sides.
//!
//! A job runs on a thread of its own, with Rust's default stack, so a panic
//! inside it is contained, the stack it gets does not depend on the Dart
//! worker isolate that calls in here, and that isolate stays free to poll
//! the job and to pass on a cancel while the solve runs. The vendored elkrs
//! walks graphs with explicit stacks rather than recursion, so a
//! ten-thousand-cell chain needs no more stack than a ten-cell one; its
//! `tests/deep_graphs.rs` lays such chains out on a 1 MiB thread.
//!
//! Cancel is cooperative: elkrs checks the job's token at every pipeline
//! step and inside its long loops, and a cancelled job finishes promptly
//! with status 2 and no document.

use std::slice;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU64, Ordering};
use std::thread::JoinHandle;

use elkrs::core::progress::{CancelToken, LayoutError, LayoutMonitor, Phase};

/// `*status` of a finished job: the buffer is the laid-out document.
pub const ELK_STATUS_OK: i32 = 0;
/// `*status` of a finished job: the buffer is an error message.
pub const ELK_STATUS_ERROR: i32 = 1;
/// `*status` of a finished job: it was cancelled; the buffer is a message.
pub const ELK_STATUS_CANCELLED: i32 = 2;

/// Allocates `len` zeroed bytes the caller may fill (the input document) and
/// must release with [`elk_free`]. Never returns null; a zero length still
/// yields a one-byte allocation so the pointer stays valid.
#[unsafe(no_mangle)]
pub extern "C" fn elk_alloc(len: usize) -> *mut u8 {
    Box::into_raw(vec![0u8; len.max(1)].into_boxed_slice()) as *mut u8
}

/// Releases a buffer of `len` bytes that came from [`elk_alloc`],
/// [`elk_layout_json`] or [`elk_job_finish`]. A null pointer is ignored.
///
/// # Safety
/// `ptr` must be a pointer this library handed out, with the `len` it was
/// handed out with, and must not be used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn elk_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len.max(1))) });
}

/// What the layout thread publishes and the caller polls.
#[derive(Default)]
struct Shared {
    /// [`phase_code`] of the latest report, 0 before the first.
    phase: AtomicI32,
    /// The latest report's fraction as `f64` bits, NaN when unknown.
    fraction: AtomicU64,
    /// Set once the thread has its result.
    done: AtomicBool,
}

/// One layout in progress, owned by the caller between [`elk_job_start`] and
/// [`elk_job_finish`].
pub struct ElkJob {
    cancel: CancelToken,
    shared: Arc<Shared>,
    thread: Option<JoinHandle<Result<String, LayoutError>>>,
    /// Set instead of `thread` when the thread could not start.
    failed: Option<String>,
}

/// The progress codes [`elk_job_poll`] writes: 1 cycle breaking, 2 layering,
/// 3 crossing minimization, 4 node placement, 5 edge routing, 0 none yet or
/// a phase this build does not know.
fn phase_code(phase: Phase) -> i32 {
    match phase {
        Phase::CycleBreaking => 1,
        Phase::Layering => 2,
        Phase::CrossingMinimization => 3,
        Phase::NodePlacement => 4,
        Phase::EdgeRouting => 5,
        _ => 0,
    }
}

fn solve(input: &str, monitor: LayoutMonitor) -> Result<String, LayoutError> {
    elkrs::create_elk()
        .layout_json_with_monitor(input, monitor)
        .and_then(|value| {
            serde_json::to_string(&value).map_err(|e| LayoutError::Failed(e.to_string()))
        })
}

impl ElkJob {
    fn start(input: String) -> ElkJob {
        let cancel = CancelToken::new();
        let shared = Arc::new(Shared::default());
        shared.fraction.store(f64::NAN.to_bits(), Ordering::Relaxed);
        let thread_cancel = cancel.clone();
        let thread_shared = shared.clone();
        let spawned = std::thread::Builder::new()
            .name("elk-layout".to_owned())
            .spawn(move || {
                let reports = thread_shared.clone();
                let monitor = LayoutMonitor::new()
                    .cancel_token(thread_cancel)
                    .on_progress(move |p| {
                        let fraction = p.fraction.unwrap_or(f64::NAN);
                        reports
                            .fraction
                            .store(fraction.to_bits(), Ordering::Relaxed);
                        reports.phase.store(phase_code(p.phase), Ordering::Release);
                    });
                let result = solve(&input, monitor);
                thread_shared.done.store(true, Ordering::Release);
                result
            });
        match spawned {
            Ok(handle) => ElkJob {
                cancel,
                shared,
                thread: Some(handle),
                failed: None,
            },
            Err(e) => {
                shared.done.store(true, Ordering::Release);
                ElkJob {
                    cancel,
                    shared,
                    thread: None,
                    failed: Some(format!("could not start the layout thread: {e}")),
                }
            }
        }
    }

    /// Waits for the thread and returns the buffer and its status.
    fn finish(mut self) -> (Vec<u8>, i32) {
        let result = match (self.thread.take(), self.failed.take()) {
            (Some(handle), _) => handle
                .join()
                .unwrap_or_else(|_| Err(LayoutError::Failed("the layout thread panicked".into()))),
            (None, failed) => Err(LayoutError::Failed(failed.unwrap_or_default())),
        };
        match result {
            Ok(json) => (json.into_bytes(), ELK_STATUS_OK),
            Err(LayoutError::Cancelled) => (
                LayoutError::Cancelled.to_string().into_bytes(),
                ELK_STATUS_CANCELLED,
            ),
            Err(LayoutError::Failed(message)) => (message.into_bytes(), ELK_STATUS_ERROR),
        }
    }
}

/// Hands `bytes` to the caller as a buffer for [`elk_free`].
///
/// # Safety
/// `out_len` and `status` must be valid for writes.
unsafe fn hand_over(bytes: Vec<u8>, code: i32, out_len: *mut usize, status: *mut i32) -> *mut u8 {
    unsafe {
        *out_len = bytes.len();
        *status = code;
    }
    Box::into_raw(bytes.into_boxed_slice()) as *mut u8
}

/// Starts laying out the ELK JSON document in `ptr[0..len]` (copied, so the
/// caller may release it at once) and returns the job. Never returns null.
/// Poll it with [`elk_job_poll`], stop it with [`elk_job_cancel`], and
/// always end it with [`elk_job_finish`], which releases it.
///
/// # Safety
/// `ptr` must point at `len` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn elk_job_start(ptr: *const u8, len: usize) -> *mut ElkJob {
    let input = String::from_utf8_lossy(unsafe { slice::from_raw_parts(ptr, len) }).into_owned();
    Box::into_raw(Box::new(ElkJob::start(input)))
}

/// Returns 1 once the job has finished (its result is ready for
/// [`elk_job_finish`], which will not block), else 0. Writes the latest
/// progress: `*phase` a code (1 cycle breaking, 2 layering, 3 crossing
/// minimization, 4 node placement, 5 edge routing, 0 none yet) and
/// `*fraction` the share of the layout done, in [0, 1), or NaN when unknown.
///
/// # Safety
/// `job` must come from [`elk_job_start`] and not yet be finished; `phase`
/// and `fraction` must be valid for writes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn elk_job_poll(
    job: *const ElkJob,
    phase: *mut i32,
    fraction: *mut f64,
) -> i32 {
    let job = unsafe { &*job };
    let shared = &job.shared;
    unsafe {
        *phase = shared.phase.load(Ordering::Acquire);
        *fraction = f64::from_bits(shared.fraction.load(Ordering::Relaxed));
    }
    i32::from(shared.done.load(Ordering::Acquire))
}

/// Asks the job to stop. It finishes at elkrs's next check, within a
/// pipeline step, and [`elk_job_finish`] then reports status 2. Harmless on
/// a job that has already finished.
///
/// # Safety
/// `job` must come from [`elk_job_start`] and not yet be finished.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn elk_job_cancel(job: *const ElkJob) {
    unsafe { &*job }.cancel.cancel();
}

/// Waits for the job (immediately, once [`elk_job_poll`] has returned 1),
/// releases it and returns a new buffer with its outcome. `*out_len`
/// receives the buffer length and `*status` is 0 when the buffer is the
/// laid-out document, 1 when it is an error message (invalid JSON, an option
/// ELK rejects, a panic inside the solve) and 2 when the job was cancelled.
/// The buffer is released with [`elk_free`] either way.
///
/// # Safety
/// `job` must come from [`elk_job_start`] and is invalid afterwards;
/// `out_len` and `status` must be valid for writes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn elk_job_finish(
    job: *mut ElkJob,
    out_len: *mut usize,
    status: *mut i32,
) -> *mut u8 {
    let job = unsafe { Box::from_raw(job) };
    let (bytes, code) = job.finish();
    unsafe { hand_over(bytes, code, out_len, status) }
}

/// Lays out the ELK JSON document in `ptr[0..len]` and returns a new buffer
/// holding the result: [`elk_job_start`] and [`elk_job_finish`] in one call,
/// for a caller that neither polls nor cancels. `*status` is 0 or 1 as for
/// [`elk_job_finish`].
///
/// # Safety
/// `ptr` must point at `len` readable bytes, and `out_len` and `status` must
/// be valid for writes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn elk_layout_json(
    ptr: *const u8,
    len: usize,
    out_len: *mut usize,
    status: *mut i32,
) -> *mut u8 {
    let input = String::from_utf8_lossy(unsafe { slice::from_raw_parts(ptr, len) }).into_owned();
    let (bytes, code) = ElkJob::start(input).finish();
    unsafe { hand_over(bytes, code, out_len, status) }
}

/// The elkrs version this library was built against, as a NUL-terminated
/// static string. For the About box and the stderr announcement.
#[unsafe(no_mangle)]
pub extern "C" fn elk_engine_version() -> *const u8 {
    concat!("elkrs ", env!("ELK_FFI_ELKRS_VERSION"), "\0").as_ptr()
}

#[cfg(test)]
mod tests {
    use super::*;

    const TWO_NODES: &str = r#"{"id":"root","layoutOptions":{"elk.algorithm":"layered"},
        "children":[{"id":"a","width":10,"height":10},{"id":"b","width":10,"height":10}],
        "edges":[{"id":"e","sources":["a"],"targets":["b"]}]}"#;

    /// A chain long enough that a cancel lands while it is being laid out.
    fn long_chain(n: usize) -> String {
        let children: Vec<String> = (0..n)
            .map(|i| format!(r#"{{"id":"n{i}","width":20,"height":20}}"#))
            .collect();
        let edges: Vec<String> = (1..n)
            .map(|i| {
                format!(
                    r#"{{"id":"e{i}","sources":["n{}"],"targets":["n{i}"]}}"#,
                    i - 1
                )
            })
            .collect();
        format!(
            r#"{{"id":"root","layoutOptions":{{"elk.algorithm":"layered"}},"children":[{}],"edges":[{}]}}"#,
            children.join(","),
            edges.join(",")
        )
    }

    fn run(input: &str) -> (String, i32) {
        let mut out_len = 0usize;
        let mut status = -1i32;
        let ptr =
            unsafe { elk_layout_json(input.as_ptr(), input.len(), &mut out_len, &mut status) };
        let text =
            String::from_utf8(unsafe { slice::from_raw_parts(ptr, out_len) }.to_vec()).unwrap();
        unsafe { elk_free(ptr, out_len) };
        (text, status)
    }

    fn finish(job: *mut ElkJob) -> (String, i32) {
        let mut out_len = 0usize;
        let mut status = -1i32;
        let ptr = unsafe { elk_job_finish(job, &mut out_len, &mut status) };
        let text =
            String::from_utf8(unsafe { slice::from_raw_parts(ptr, out_len) }.to_vec()).unwrap();
        unsafe { elk_free(ptr, out_len) };
        (text, status)
    }

    #[test]
    fn a_job_gives_the_same_bytes_as_the_one_call_entry_point() {
        let (direct, status) = run(TWO_NODES);
        assert_eq!(status, ELK_STATUS_OK);
        let job = unsafe { elk_job_start(TWO_NODES.as_ptr(), TWO_NODES.len()) };
        let (mut phase, mut fraction) = (0, 0.0);
        while unsafe { elk_job_poll(job, &mut phase, &mut fraction) } == 0 {
            std::thread::yield_now();
        }
        assert_eq!(phase, 5, "the last report is edge routing");
        assert!((0.0..1.0).contains(&fraction));
        assert_eq!(finish(job), (direct, ELK_STATUS_OK));
    }

    #[test]
    fn a_cancelled_job_finishes_with_status_2_and_no_document() {
        let input = long_chain(3000);
        let job = unsafe { elk_job_start(input.as_ptr(), input.len()) };
        unsafe { elk_job_cancel(job) };
        let (text, status) = finish(job);
        assert_eq!(status, ELK_STATUS_CANCELLED);
        assert_eq!(text, "layout cancelled");
    }

    #[test]
    fn a_cancel_after_the_job_finished_changes_nothing() {
        let job = unsafe { elk_job_start(TWO_NODES.as_ptr(), TWO_NODES.len()) };
        let (mut phase, mut fraction) = (0, 0.0);
        while unsafe { elk_job_poll(job, &mut phase, &mut fraction) } == 0 {
            std::thread::yield_now();
        }
        unsafe { elk_job_cancel(job) };
        assert_eq!(finish(job).1, ELK_STATUS_OK);
    }

    #[test]
    fn a_rejected_input_is_an_error_not_a_cancel() {
        let (text, status) = run("{ not json");
        assert_eq!(status, ELK_STATUS_ERROR);
        assert!(text.starts_with("invalid JSON"), "{text}");
    }
}
