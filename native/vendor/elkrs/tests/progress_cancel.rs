//! Progress reports and cooperative cancellation through
//! `Elk::layout_json_with_monitor`.
//!
//! The monitor only observes, so a monitored layout that is not cancelled
//! must produce exactly the bytes an unmonitored one does; a cancelled one
//! must return `LayoutError::Cancelled` and nothing else.

#![cfg(not(target_arch = "wasm32"))]

use std::cell::RefCell;
use std::rc::Rc;
use std::sync::mpsc;

use elkrs::core::progress::{CancelToken, LayoutError, LayoutMonitor, Phase, Progress};

#[path = "support/netlist.rs"]
mod netlist;

/// A monitor that records every report into the returned list.
fn recording_monitor() -> (LayoutMonitor, Rc<RefCell<Vec<Progress>>>) {
    let seen = Rc::new(RefCell::new(Vec::new()));
    let sink = seen.clone();
    let monitor = LayoutMonitor::new().on_progress(move |p| sink.borrow_mut().push(p));
    (monitor, seen)
}

fn corpus_case(name: &str) -> Option<String> {
    let dir = netlist::corpus_dir()?;
    Some(netlist::read_gz(
        &dir.join("cases").join(format!("{name}.json.gz")),
    ))
}

fn phase_rank(phase: Phase) -> u8 {
    match phase {
        Phase::CycleBreaking => 0,
        Phase::Layering => 1,
        Phase::CrossingMinimization => 2,
        Phase::NodePlacement => 3,
        Phase::EdgeRouting => 4,
        _ => unreachable!("no other phases yet"),
    }
}

/// Every golden case and two netlist cases, laid out with a monitor that
/// records progress and holds a live token, gives the same bytes (or the
/// same error) as the unmonitored call.
#[test]
fn a_monitored_layout_is_byte_identical_to_an_unmonitored_one() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let goldens = root.join("goldens/cases");
    if !goldens.is_dir() {
        eprintln!("goldens/cases not present, skipping");
        return;
    }
    let mut inputs: Vec<(String, String)> = Vec::new();
    let mut paths: Vec<_> = std::fs::read_dir(&goldens)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "json"))
        .collect();
    paths.sort();
    for path in paths {
        let name = path.file_stem().unwrap().to_string_lossy().into_owned();
        inputs.push((name, std::fs::read_to_string(&path).unwrap()));
    }
    // The two smaller netlist scopes; the two large ones would add a minute
    // to a debug run and exercise nothing these do not.
    for name in ["vexriscv_DataCache", "vexriscv_InstructionCache"] {
        if let Some(input) = corpus_case(name) {
            inputs.push((name.to_owned(), input));
        }
    }

    let elk = elkrs::create_elk();
    let mut reported = 0;
    for (name, input) in &inputs {
        let plain = elk
            .layout_json(input)
            .map(|v| serde_json::to_string(&v).unwrap());
        let (monitor, seen) = recording_monitor();
        let monitored = elk
            .layout_json_with_monitor(input, monitor.cancel_token(CancelToken::new()))
            .map(|v| serde_json::to_string(&v).unwrap());
        match (plain, monitored) {
            (Ok(a), Ok(b)) => assert!(a == b, "{name}: monitored output differs"),
            (Err(a), Err(LayoutError::Failed(b))) => assert_eq!(a, b, "{name}"),
            (a, b) => panic!("{name}: {a:?} vs {b:?}"),
        }
        reported += seen.borrow().len();
    }
    assert!(reported > 0, "no case reported progress");
}

/// Phases arrive in pipeline order, all five for each connected component,
/// with non-decreasing fractions in [0, 1) across the whole graph.
#[test]
fn progress_arrives_in_phase_order() {
    let Some(input) = corpus_case("vexriscv_InstructionCache") else {
        return;
    };
    let (monitor, seen) = recording_monitor();
    elkrs::create_elk()
        .layout_json_with_monitor(&input, monitor)
        .expect("layout");
    let seen = seen.borrow();
    assert!(!seen.is_empty());
    let mut last_fraction = 0.0;
    let mut phases = Vec::new();
    for p in seen.iter() {
        let fraction = p.fraction.expect("ELK Layered knows its step count");
        assert!((0.0..1.0).contains(&fraction), "fraction {fraction}");
        assert!(fraction >= last_fraction, "fraction went back");
        last_fraction = fraction;
        if phases.last() != Some(&p.phase) {
            phases.push(p.phase);
        }
    }
    // One full run of the five phases per connected component.
    let one_run = [
        Phase::CycleBreaking,
        Phase::Layering,
        Phase::CrossingMinimization,
        Phase::NodePlacement,
        Phase::EdgeRouting,
    ];
    assert!(phases.len() >= one_run.len());
    for run in phases.chunks(one_run.len()) {
        assert_eq!(run, one_run);
    }
}

/// A graph whose connected components are laid out one after another
/// restarts the phases per component, so only the fraction is monotonic.
#[test]
fn components_report_one_run_each_under_one_fraction() {
    let input = r#"{"id":"root","layoutOptions":{"elk.algorithm":"layered"},
        "children":[{"id":"a","width":10,"height":10},{"id":"b","width":10,"height":10},
                    {"id":"c","width":10,"height":10},{"id":"d","width":10,"height":10}],
        "edges":[{"id":"e1","sources":["a"],"targets":["b"]},
                 {"id":"e2","sources":["c"],"targets":["d"]}]}"#;
    let (monitor, seen) = recording_monitor();
    elkrs::create_elk()
        .layout_json_with_monitor(input, monitor)
        .expect("layout");
    let seen = seen.borrow();
    let restarts = seen
        .windows(2)
        .filter(|w| phase_rank(w[1].phase) < phase_rank(w[0].phase))
        .count();
    assert_eq!(restarts, 1, "two components, so the phases restart once");
    let fractions: Vec<f64> = seen.iter().map(|p| p.fraction.unwrap()).collect();
    assert!(fractions.windows(2).all(|w| w[0] <= w[1]));
    assert!(*fractions.last().unwrap() > 0.5);
}

#[test]
fn a_token_cancelled_up_front_returns_before_any_report() {
    let token = CancelToken::new();
    token.cancel();
    let (monitor, seen) = recording_monitor();
    let input = r#"{"id":"root","children":[{"id":"a","width":10,"height":10}]}"#;
    let result = elkrs::create_elk().layout_json_with_monitor(input, monitor.cancel_token(token));
    assert_eq!(result, Err(LayoutError::Cancelled));
    assert!(seen.borrow().is_empty());
}

/// Cancelling from the progress callback stops the run at its next check:
/// no later report arrives and no graph comes back.
#[test]
fn cancel_from_the_callback_stops_the_run() {
    let Some(input) = corpus_case("vexriscv_InstructionCache") else {
        return;
    };
    let token = CancelToken::new();
    let from_callback = token.clone();
    let seen = Rc::new(RefCell::new(Vec::new()));
    let sink = seen.clone();
    let monitor = LayoutMonitor::new()
        .cancel_token(token)
        .on_progress(move |p: Progress| {
            sink.borrow_mut().push(p.phase);
            if p.phase == Phase::NodePlacement {
                from_callback.cancel();
            }
        });
    let result = elkrs::create_elk().layout_json_with_monitor(&input, monitor);
    assert_eq!(result, Err(LayoutError::Cancelled));
    let seen = seen.borrow();
    assert_eq!(seen.last(), Some(&Phase::NodePlacement));
    assert_eq!(
        seen.iter().filter(|&&p| p == Phase::NodePlacement).count(),
        1
    );
}

/// The usual shape: the layout runs on a worker thread and another thread
/// cancels it while crossing minimization is under way.
#[test]
fn cancel_from_another_thread_while_a_phase_runs() {
    let Some(input) = corpus_case("vexriscv_DataCache") else {
        return;
    };
    let token = CancelToken::new();
    let worker_token = token.clone();
    let (reports, phases) = mpsc::channel::<Phase>();
    let (resume, resumed) = mpsc::channel::<()>();
    let worker = std::thread::spawn(move || {
        let monitor =
            LayoutMonitor::new()
                .cancel_token(worker_token)
                .on_progress(move |p: Progress| {
                    let _ = reports.send(p.phase);
                    if p.phase == Phase::CrossingMinimization {
                        // Hold the phase open until the other thread has cancelled.
                        let _ = resumed.recv();
                    }
                });
        elkrs::create_elk().layout_json_with_monitor(&input, monitor)
    });
    loop {
        let phase = phases
            .recv()
            .expect("the layout ended before crossing minimization");
        if phase == Phase::CrossingMinimization {
            token.cancel();
            resume.send(()).unwrap();
            break;
        }
    }
    let result = worker.join().expect("layout thread");
    assert_eq!(result, Err(LayoutError::Cancelled));
    let later: Vec<Phase> = phases.try_iter().collect();
    assert!(later.is_empty(), "reports after the cancel: {later:?}");
}

#[test]
fn invalid_input_is_a_failure_not_a_cancel() {
    let result = elkrs::create_elk().layout_json_with_monitor("{ not json", LayoutMonitor::new());
    assert!(matches!(result, Err(LayoutError::Failed(m)) if m.starts_with("invalid JSON")));
}
