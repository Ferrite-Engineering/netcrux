//! A long chain of ported nodes, shared by `tests/deep_graphs.rs` and
//! `tests/wasm.rs`.

use serde_json::{Value, json};

/// A chain of `n` nodes, each with a west input port and an east output
/// port, wired `n{i}.o -> n{i+1}.i`. With `feedback`, a last-to-first edge
/// closes the chain into one long cycle so cycle breaking has work to do.
pub fn chain(n: usize, feedback: bool, options: Value) -> String {
    let mut children = Vec::with_capacity(n);
    let mut edges = Vec::with_capacity(n);
    for i in 0..n {
        children.push(json!({
            "id": format!("n{i}"),
            "width": 80,
            "height": 52,
            "ports": [
                {"id": format!("n{i}.i"), "width": 4, "height": 4,
                 "layoutOptions": {"elk.port.side": "WEST"}},
                {"id": format!("n{i}.o"), "width": 4, "height": 4,
                 "layoutOptions": {"elk.port.side": "EAST"}}
            ],
            "layoutOptions": {"elk.portConstraints": "FIXED_SIDE"}
        }));
        if i + 1 < n {
            edges.push(json!({
                "id": format!("e{i}"),
                "sources": [format!("n{i}.o")],
                "targets": [format!("n{}.i", i + 1)]
            }));
        }
    }
    if feedback {
        edges.push(json!({
            "id": "back",
            "sources": [format!("n{}.o", n - 1)],
            "targets": ["n0.i"]
        }));
    }
    json!({
        "id": "root",
        "layoutOptions": options,
        "children": children,
        "edges": edges
    })
    .to_string()
}

/// The option set a schematic viewer uses for a large scope, with the
/// given cycle-breaking strategy.
pub fn large_scope_options(cycle_breaking: &str) -> Value {
    json!({
        "elk.algorithm": "layered",
        "elk.direction": "RIGHT",
        "elk.spacing.nodeNode": "20",
        "elk.layered.spacing.nodeNodeBetweenLayers": "30",
        "elk.layered.thoroughness": "1",
        "elk.layered.cycleBreaking.strategy": cycle_breaking
    })
}
