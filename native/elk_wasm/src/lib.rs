// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

//! The NetCrux web viewer's layout engine: the vendored elkrs port compiled
//! to WebAssembly, with the same contract as `native/elk_ffi`. One function
//! takes an ELK JSON document and returns the laid-out ELK JSON document,
//! serialised exactly as the desktop library serialises it, so desktop and
//! browser produce the same bytes for the same input.
//!
//! Single-threaded, so the page needs no cross-origin isolation. The solve
//! is synchronous; `web/wasm/elk_wasm_worker.js` runs it inside a dedicated
//! Web Worker so the page stays responsive, posts the progress reports the
//! solve makes along the way, and terminating that worker is how a solve is
//! cancelled. elkrs walks graphs on explicit stacks, so deep graphs fit the
//! default wasm stack.

use elkrs::core::progress::{LayoutMonitor, Progress};
use wasm_bindgen::prelude::*;

/// Lays out `input` and returns the result as compact JSON text, or the
/// reason it could not (invalid JSON, an option ELK rejects).
pub fn layout(input: &str) -> Result<String, String> {
    layout_monitored(input, LayoutMonitor::new())
}

/// [`layout`], reporting progress to `monitor`. Same output.
pub fn layout_monitored(input: &str, monitor: LayoutMonitor) -> Result<String, String> {
    elkrs::create_elk()
        .layout_json_with_monitor(input, monitor)
        .map_err(|e| e.to_string())
        .and_then(|value| serde_json::to_string(&value).map_err(|e| e.to_string()))
}

#[wasm_bindgen]
extern "C" {
    /// A JavaScript `(phase, fraction) => void`: `phase` an elkrs phase name
    /// such as `"node placement"`, `fraction` the share of the layout done,
    /// `NaN` when unknown.
    pub type ProgressCallback;

    #[wasm_bindgen(method, js_name = call)]
    fn call(this: &ProgressCallback, this_arg: &JsValue, phase: &str, fraction: f64);
}

/// The JavaScript entry point over [`layout`]. A rejected input throws a JS
/// `Error` carrying the reason. A panic traps the module (`panic = "abort"`),
/// which the worker reports as fatal so the caller starts a fresh one.
#[wasm_bindgen(js_name = layoutJson)]
pub fn layout_json(input: &str) -> Result<String, JsError> {
    console_error_panic_hook::set_once();
    layout(input).map_err(|message| JsError::new(&message))
}

/// [`layout_json`], calling `on_progress` at each pipeline step of the
/// solve. Same output.
#[wasm_bindgen(js_name = layoutJsonWithProgress)]
pub fn layout_json_with_progress(
    input: &str,
    on_progress: ProgressCallback,
) -> Result<String, JsError> {
    console_error_panic_hook::set_once();
    let monitor = LayoutMonitor::new().on_progress(move |p: Progress| {
        on_progress.call(
            &JsValue::UNDEFINED,
            p.phase.name(),
            p.fraction.unwrap_or(f64::NAN),
        );
    });
    layout_monitored(input, monitor).map_err(|message| JsError::new(&message))
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::rc::Rc;

    use super::{layout, layout_monitored};
    use elkrs::core::progress::{LayoutMonitor, Phase};

    const TWO_NODES: &str = r#"{"id":"root","layoutOptions":{"elk.algorithm":"layered"},
        "children":[{"id":"a","width":10,"height":10},{"id":"b","width":10,"height":10}],
        "edges":[{"id":"e","sources":["a"],"targets":["b"]}]}"#;

    #[test]
    fn lays_out_a_two_node_graph() {
        let out = layout(TWO_NODES).expect("layout");
        assert!(out.starts_with('{') && out.contains("\"x\""));
    }

    #[test]
    fn reports_progress_and_gives_the_same_bytes() {
        let phases = Rc::new(RefCell::new(Vec::new()));
        let sink = phases.clone();
        let monitor = LayoutMonitor::new().on_progress(move |p| sink.borrow_mut().push(p.phase));
        let watched = layout_monitored(TWO_NODES, monitor).expect("layout");
        assert_eq!(watched, layout(TWO_NODES).expect("layout"));
        assert_eq!(phases.borrow().first(), Some(&Phase::CycleBreaking));
        assert_eq!(phases.borrow().last(), Some(&Phase::EdgeRouting));
    }

    #[test]
    fn rejects_invalid_json_with_a_reason() {
        let err = layout("{ not json").expect_err("invalid input");
        assert!(!err.is_empty());
    }
}
