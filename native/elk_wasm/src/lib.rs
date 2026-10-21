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
//! Web Worker so the page stays responsive, and terminating that worker is
//! how a solve is cancelled. elkrs walks graphs on explicit stacks, so deep
//! graphs fit the default wasm stack.

use wasm_bindgen::prelude::*;

/// Lays out `input` and returns the result as compact JSON text, or the
/// reason it could not (invalid JSON, an option ELK rejects).
pub fn layout(input: &str) -> Result<String, String> {
    elkrs::create_elk()
        .layout_json(input)
        .and_then(|value| serde_json::to_string(&value).map_err(|e| e.to_string()))
}

/// The JavaScript entry point over [`layout`]. A rejected input throws a JS
/// `Error` carrying the reason. A panic traps the module (`panic = "abort"`),
/// which the worker reports as fatal so the caller starts a fresh one.
#[wasm_bindgen(js_name = layoutJson)]
pub fn layout_json(input: &str) -> Result<String, JsError> {
    console_error_panic_hook::set_once();
    layout(input).map_err(|message| JsError::new(&message))
}

#[cfg(test)]
mod tests {
    use super::layout;

    #[test]
    fn lays_out_a_two_node_graph() {
        let input = r#"{"id":"root","layoutOptions":{"elk.algorithm":"layered"},
            "children":[{"id":"a","width":10,"height":10},{"id":"b","width":10,"height":10}],
            "edges":[{"id":"e","sources":["a"],"targets":["b"]}]}"#;
        let out = layout(input).expect("layout");
        assert!(out.starts_with('{') && out.contains("\"x\""));
    }

    #[test]
    fn rejects_invalid_json_with_a_reason() {
        let err = layout("{ not json").expect_err("invalid input");
        assert!(!err.is_empty());
    }
}
