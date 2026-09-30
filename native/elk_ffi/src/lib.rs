// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

//! The C ABI NetCrux's desktop layout host calls: one function that takes an
//! ELK JSON document and returns the laid-out ELK JSON document, plus the
//! allocator pair the caller uses for the byte buffers on both sides.
//!
//! The solve runs on a thread with a 256 MiB stack of its own. ELK Layered's
//! depth-first cycle breaker and network-simplex tree walks recurse once per
//! layer, so a ten-thousand-cell chain is ten thousand frames deep; the Dart
//! worker isolate that calls in here has a stack no larger than 1 MiB, and
//! that budget must never be what decides whether a scope lays out.

use std::slice;

/// Allocates `len` zeroed bytes the caller may fill (the input document) and
/// must release with [`elk_free`]. Never returns null; a zero length still
/// yields a one-byte allocation so the pointer stays valid.
#[unsafe(no_mangle)]
pub extern "C" fn elk_alloc(len: usize) -> *mut u8 {
    Box::into_raw(vec![0u8; len.max(1)].into_boxed_slice()) as *mut u8
}

/// Releases a buffer of `len` bytes that came from [`elk_alloc`] or from
/// [`elk_layout_json`]. A null pointer is ignored.
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

/// Lays out the ELK JSON document in `ptr[0..len]` and returns a new buffer
/// holding the result. `*out_len` receives the buffer length and `*status`
/// is 0 when the buffer is the laid-out document, 1 when it is an error
/// message (invalid JSON, an option ELK rejects, a panic inside the solve).
/// The buffer is released with [`elk_free`] either way.
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
    let result = std::thread::Builder::new()
        .name("elk-layout".to_owned())
        .stack_size(256 * 1024 * 1024)
        .spawn(move || {
            elkrs::create_elk()
                .layout_json(&input)
                .and_then(|value| serde_json::to_string(&value).map_err(|e| e.to_string()))
        })
        .map_err(|e| format!("could not start the layout thread: {e}"))
        .and_then(|handle| {
            handle
                .join()
                .unwrap_or_else(|_| Err("the layout thread panicked".to_owned()))
        });
    let (bytes, code) = match result {
        Ok(json) => (json.into_bytes(), 0),
        Err(message) => (message.into_bytes(), 1),
    };
    unsafe {
        *out_len = bytes.len();
        *status = code;
    }
    Box::into_raw(bytes.into_boxed_slice()) as *mut u8
}

/// The elkrs version this library was built against, as a NUL-terminated
/// static string. For the About box and the stderr announcement.
#[unsafe(no_mangle)]
pub extern "C" fn elk_engine_version() -> *const u8 {
    concat!("elkrs ", env!("ELK_FFI_ELKRS_VERSION"), "\0").as_ptr()
}
