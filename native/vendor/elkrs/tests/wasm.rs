//! The crate on `wasm32-unknown-unknown`, run under Node:
//!
//!     wasm-pack test --node --release
//!
//! Golden cases embedded at compile time (there is no file system), the
//! clock-free random seed, and a long chain on the default 1 MiB wasm stack.

#![cfg(target_arch = "wasm32")]

use std::io::Read;

use serde_json::Value;
use wasm_bindgen_test::wasm_bindgen_test;

#[path = "support/chain.rs"]
mod chain;
#[path = "support/netlist.rs"]
mod netlist;

/// `goldens.rs`'s comparison: keys exact, numbers equal as f64.
fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Object(ma), Value::Object(mb)) => {
            ma.len() == mb.len()
                && ma
                    .iter()
                    .all(|(k, va)| mb.get(k).is_some_and(|vb| same(va, vb)))
        }
        (Value::Array(aa), Value::Array(ab)) => {
            aa.len() == ab.len() && aa.iter().zip(ab).all(|(x, y)| same(x, y))
        }
        (Value::Number(na), Value::Number(nb)) => na.as_f64() == nb.as_f64(),
        _ => a == b,
    }
}

fn golden(input: &str, expected: &str) {
    let actual = elkrs::create_elk().layout_json(input).expect("layout");
    let expected: Value = serde_json::from_str(expected).unwrap();
    assert!(same(&expected, &actual), "differs from the Java oracle");
}

#[wasm_bindgen_test]
fn golden_layered_ports_fixed() {
    golden(
        include_str!("../goldens/cases/layered_ports_fixed.json"),
        include_str!("../goldens/expected/layered_ports_fixed.json"),
    );
}

#[wasm_bindgen_test]
fn golden_force_seeded() {
    golden(
        include_str!("../goldens/cases/force_seeded.json"),
        include_str!("../goldens/expected/force_seeded.json"),
    );
}

#[wasm_bindgen_test]
fn golden_stress_basic() {
    golden(
        include_str!("../goldens/cases/stress_basic.json"),
        include_str!("../goldens/expected/stress_basic.json"),
    );
}

fn gunzip(bytes: &[u8]) -> String {
    let mut text = String::new();
    flate2::read::GzDecoder::new(bytes)
        .read_to_string(&mut text)
        .unwrap();
    text
}

#[wasm_bindgen_test]
fn netlist_corpus_instruction_cache() {
    let input = gunzip(include_bytes!(
        "../goldens/netlists/cases/vexriscv_InstructionCache.json.gz"
    ));
    let expected: std::collections::BTreeMap<String, Vec<f64>> = serde_json::from_str(&gunzip(
        include_bytes!("../goldens/netlists/expected/vexriscv_InstructionCache.geometry.json.gz"),
    ))
    .unwrap();
    let layout = elkrs::create_elk().layout_json(&input).expect("layout");
    assert!(netlist::geometry(&layout) == expected, "differs from elkjs");
}

/// `randomSeed = 0` asks for a clock seed; there is no clock here.
#[wasm_bindgen_test]
fn force_with_random_seed_zero() {
    let input = r#"{
        "id": "root",
        "layoutOptions": {"elk.algorithm": "force", "elk.randomSeed": "0"},
        "children": [
            {"id": "a", "width": 30, "height": 30},
            {"id": "b", "width": 30, "height": 30},
            {"id": "c", "width": 30, "height": 30}
        ],
        "edges": [
            {"id": "ab", "sources": ["a"], "targets": ["b"]},
            {"id": "bc", "sources": ["b"], "targets": ["c"]}
        ]
    }"#;
    let elk = elkrs::create_elk();
    let first = elk.layout_json(input).expect("layout");
    let second = elk.layout_json(input).expect("layout");
    assert!(same(&first, &second), "the fallback seed is fixed");
}

/// Ten thousand nodes deep on the default wasm stack.
#[wasm_bindgen_test]
fn long_chain_on_the_wasm_stack() {
    let n = 10_000;
    let input = chain::chain(n, true, chain::large_scope_options("DEPTH_FIRST"));
    let layout = elkrs::create_elk().layout_json(&input).expect("layout");
    assert_eq!(layout["children"].as_array().map_or(0, Vec::len), n);
}
