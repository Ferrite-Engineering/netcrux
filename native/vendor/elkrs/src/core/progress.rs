//! Progress reporting and cooperative cancellation for one layout run, the
//! part of ELK's `IElkProgressMonitor` a caller needs to show progress and
//! to stop a long layout.
//!
//! A [`LayoutMonitor`] is installed for the duration of
//! [`crate::core::Elk::layout_json_with_monitor`] or
//! [`crate::core::engine::RecursiveGraphLayoutEngine::layout_with_monitor`],
//! scoped to the calling thread, so no algorithm signature changes to carry
//! it. Algorithms call [`report`] at phase boundaries and
//! [`check_cancelled`] or [`is_cancelled`] inside their long loops. With no
//! monitor installed every one of these is a no-op, and a monitor only
//! observes: it never changes what a layout computes, only whether the run
//! is allowed to finish.

use std::cell::RefCell;
use std::fmt;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

/// The error text an algorithm returns when it stops because the run was
/// cancelled. Callers of the monitored entry points see
/// [`LayoutError::Cancelled`] instead.
pub const CANCELLED: &str = "layout cancelled";

/// A cancellation flag shared between the thread running a layout and
/// whoever may want to stop it. Cheap to clone; every clone sets and reads
/// the same flag.
#[derive(Clone, Debug, Default)]
pub struct CancelToken(Arc<AtomicBool>);

impl CancelToken {
    pub fn new() -> Self {
        Self::default()
    }

    /// Asks the layout to stop. The run notices at its next check and
    /// returns [`LayoutError::Cancelled`].
    pub fn cancel(&self) {
        self.0.store(true, Ordering::Relaxed);
    }

    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::Relaxed)
    }
}

/// The ELK Layered phase a progress report belongs to. Intermediate
/// processors report the phase they prepare for, so phases arrive in order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub enum Phase {
    CycleBreaking,
    Layering,
    CrossingMinimization,
    NodePlacement,
    EdgeRouting,
}

impl Phase {
    /// A short English name, e.g. `"crossing minimization"`.
    pub fn name(self) -> &'static str {
        match self {
            Phase::CycleBreaking => "cycle breaking",
            Phase::Layering => "layering",
            Phase::CrossingMinimization => "crossing minimization",
            Phase::NodePlacement => "node placement",
            Phase::EdgeRouting => "edge routing",
        }
    }
}

/// One progress report.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Progress {
    /// The phase about to run.
    pub phase: Phase,
    /// How much of the current graph's layout is done, in `[0, 1)`, where
    /// the algorithm knows it. A graph with nested graphs laid out
    /// separately reports one run per graph, innermost first.
    pub fraction: Option<f64>,
}

type ProgressCallback = Box<dyn FnMut(Progress)>;

/// What a monitored layout reports to and listens to: an optional progress
/// callback and an optional cancel token.
#[derive(Default)]
pub struct LayoutMonitor {
    on_progress: Option<ProgressCallback>,
    cancel: Option<CancelToken>,
}

impl LayoutMonitor {
    pub fn new() -> Self {
        Self::default()
    }

    /// Calls `callback` at each phase boundary of the run, on the thread
    /// running the layout. The callback must not start a layout of its own
    /// on that thread.
    pub fn on_progress(mut self, callback: impl FnMut(Progress) + 'static) -> Self {
        self.on_progress = Some(Box::new(callback));
        self
    }

    /// Stops the run once `token` is cancelled.
    pub fn cancel_token(mut self, token: CancelToken) -> Self {
        self.cancel = Some(token);
        self
    }
}

impl fmt::Debug for LayoutMonitor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LayoutMonitor")
            .field("on_progress", &self.on_progress.is_some())
            .field("cancel", &self.cancel)
            .finish()
    }
}

/// Why a monitored layout produced no result.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LayoutError {
    /// The cancel token was set before the run finished. Nothing is
    /// returned, not even a partial layout.
    Cancelled,
    /// The layout failed, with the message the unmonitored entry points
    /// return.
    Failed(String),
}

impl fmt::Display for LayoutError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LayoutError::Cancelled => f.write_str(CANCELLED),
            LayoutError::Failed(message) => f.write_str(message),
        }
    }
}

impl std::error::Error for LayoutError {}

struct Active {
    on_progress: Option<ProgressCallback>,
    cancel: Option<CancelToken>,
    /// Set once any check on this run saw the token cancelled.
    cancelled: bool,
}

thread_local! {
    static ACTIVE: RefCell<Option<Active>> = const { RefCell::new(None) };
}

/// Puts the monitor that was active before a run back, also when the run
/// panics.
struct Restore(Option<Option<Active>>);

impl Drop for Restore {
    fn drop(&mut self) {
        if let Some(previous) = self.0.take() {
            ACTIVE.with(|active| *active.borrow_mut() = previous);
        }
    }
}

/// Runs `layout` with `monitor` installed on this thread. Any error after a
/// check has seen the token cancelled becomes [`LayoutError::Cancelled`],
/// and so does a run that finished after one did, since a loop that stops
/// early on cancel leaves a valid but unfinished result.
pub(crate) fn run<T>(
    monitor: LayoutMonitor,
    layout: impl FnOnce() -> Result<T, String>,
) -> Result<T, LayoutError> {
    let active = Active {
        on_progress: monitor.on_progress,
        cancel: monitor.cancel,
        cancelled: false,
    };
    let previous = ACTIVE.with(|slot| slot.replace(Some(active)));
    let _restore = Restore(Some(previous));
    let result = match check_cancelled() {
        Ok(()) => layout(),
        Err(message) => Err(message),
    };
    let cancelled = ACTIVE.with(|slot| slot.borrow().as_ref().is_some_and(|a| a.cancelled));
    match result {
        _ if cancelled => Err(LayoutError::Cancelled),
        Ok(value) => Ok(value),
        Err(message) => Err(LayoutError::Failed(message)),
    }
}

/// Reports that `phase` is about to run, `fraction` of the way through the
/// current graph's layout. A no-op without a monitor or without a callback.
pub fn report(phase: Phase, fraction: Option<f64>) {
    // The callback is taken out while it runs, so it may itself call into
    // this module (a check, a nested report) without a double borrow.
    let callback = ACTIVE.with(|slot| {
        slot.borrow_mut()
            .as_mut()
            .and_then(|active| active.on_progress.take())
    });
    if let Some(mut callback) = callback {
        callback(Progress { phase, fraction });
        ACTIVE.with(|slot| {
            if let Some(active) = slot.borrow_mut().as_mut() {
                active.on_progress = Some(callback);
            }
        });
    }
}

/// Whether the run has been cancelled. For loops that cannot return an
/// error: they stop early, leaving a valid but unfinished result, and the
/// run then returns [`LayoutError::Cancelled`] rather than that result.
pub fn is_cancelled() -> bool {
    ACTIVE.with(|slot| {
        let mut slot = slot.borrow_mut();
        let Some(active) = slot.as_mut() else {
            return false;
        };
        if !active.cancelled
            && active
                .cancel
                .as_ref()
                .is_some_and(CancelToken::is_cancelled)
        {
            active.cancelled = true;
        }
        active.cancelled
    })
}

/// `Err(CANCELLED)` once the run has been cancelled, for loops that can
/// return an error.
pub fn check_cancelled() -> Result<(), String> {
    if is_cancelled() {
        Err(CANCELLED.to_string())
    } else {
        Ok(())
    }
}

/// A phase boundary: checks for cancellation, then reports progress.
pub fn checkpoint(phase: Phase, fraction: Option<f64>) -> Result<(), String> {
    check_cancelled()?;
    report(phase, fraction);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::rc::Rc;

    #[test]
    fn without_a_monitor_everything_is_a_no_op() {
        assert!(!is_cancelled());
        assert_eq!(check_cancelled(), Ok(()));
        assert_eq!(checkpoint(Phase::Layering, Some(0.5)), Ok(()));
    }

    #[test]
    fn a_cancelled_token_stops_the_run_before_it_starts() {
        let token = CancelToken::new();
        token.cancel();
        let mut ran = false;
        let result = run(LayoutMonitor::new().cancel_token(token), || {
            ran = true;
            Ok(())
        });
        assert_eq!(result, Err(LayoutError::Cancelled));
        assert!(!ran);
    }

    #[test]
    fn a_loop_that_stops_early_turns_its_result_into_cancelled() {
        let token = CancelToken::new();
        let inner = token.clone();
        let result = run(LayoutMonitor::new().cancel_token(token), move || {
            inner.cancel();
            // A loop that cannot return an error breaks and returns normally.
            assert!(is_cancelled());
            Ok(42)
        });
        assert_eq!(result, Err(LayoutError::Cancelled));
    }

    #[test]
    fn errors_without_a_cancel_stay_failures() {
        let result: Result<(), _> = run(LayoutMonitor::new(), || Err("bad option".to_string()));
        assert_eq!(result, Err(LayoutError::Failed("bad option".to_string())));
    }

    #[test]
    fn reports_reach_the_callback_and_the_monitor_is_removed_afterwards() {
        let seen = Rc::new(RefCell::new(Vec::new()));
        let sink = seen.clone();
        let monitor = LayoutMonitor::new().on_progress(move |p| sink.borrow_mut().push(p));
        run(monitor, || {
            checkpoint(Phase::CycleBreaking, Some(0.0))?;
            checkpoint(Phase::EdgeRouting, Some(0.9))
        })
        .unwrap();
        assert_eq!(
            *seen.borrow(),
            vec![
                Progress {
                    phase: Phase::CycleBreaking,
                    fraction: Some(0.0)
                },
                Progress {
                    phase: Phase::EdgeRouting,
                    fraction: Some(0.9)
                },
            ]
        );
        report(Phase::Layering, None);
        assert_eq!(seen.borrow().len(), 2);
    }

    #[test]
    fn a_callback_may_cancel_and_the_next_check_sees_it() {
        let token = CancelToken::new();
        let from_callback = token.clone();
        let monitor = LayoutMonitor::new()
            .cancel_token(token)
            .on_progress(move |_| from_callback.cancel());
        let result = run(monitor, || {
            checkpoint(Phase::CycleBreaking, Some(0.0))?;
            checkpoint(Phase::Layering, Some(0.2))?;
            unreachable!("the second checkpoint returns the cancel")
        });
        assert_eq!(result, Err::<(), _>(LayoutError::Cancelled));
    }

    #[test]
    fn nested_runs_restore_the_outer_monitor() {
        let outer = CancelToken::new();
        let outer_handle = outer.clone();
        let result = run(LayoutMonitor::new().cancel_token(outer), || {
            let inner = run(LayoutMonitor::new(), || Ok(()));
            assert_eq!(inner, Ok(()));
            outer_handle.cancel();
            check_cancelled()
        });
        assert_eq!(result, Err(LayoutError::Cancelled));
        assert!(!is_cancelled());
    }
}
