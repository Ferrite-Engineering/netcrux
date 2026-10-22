//! Deep graphs on a small stack.
//!
//! A chain of N nodes makes every depth-first walk in ELK Layered N calls
//! deep (cycle breaking, component splitting, network-simplex tree walks).
//! Each case lays out a long chain on a thread with a 1 MiB stack, the
//! default main-thread stack on wasm32 and below the 2 MiB a spawned
//! `std::thread` gets, so a walk that recurses once per node overflows here
//! instead of in a caller's process.

#![cfg(not(target_arch = "wasm32"))]

use serde_json::{Value, json};

#[path = "support/netlist.rs"]
mod netlist;
#[path = "support/chain.rs"]
mod support;

use support::{chain, large_scope_options};

const STACK: usize = 1024 * 1024;

/// The real-netlist corpus on a 128 KiB thread. A browser runs wasm on the
/// engine's own stack, with frames several times a native build's, so a walk
/// that recurses per node overflows there on graphs this size long before a
/// native 1 MiB thread notices. Two such walks, the hyperedge dummy merger's
/// port walk and Brandes-Koepf's `place_block`, overflowed on these netlists.
#[test]
fn netlist_corpus_on_a_tight_stack() {
    let dir = netlist::corpus_dir().expect("goldens/netlists is present");
    let cases = netlist::cases(&dir);
    assert!(!cases.is_empty());
    for (name, input) in cases {
        let laid_out = std::thread::Builder::new()
            .stack_size(128 * 1024)
            .spawn(move || elkrs::create_elk().layout_json(&input).is_ok())
            .expect("spawn")
            .join()
            .expect("layout thread panicked");
        assert!(laid_out, "{name} did not lay out");
    }
}

/// Lays `input` out on a 1 MiB thread and returns the node count of the
/// result. A stack overflow aborts the test binary, which fails the run.
fn layout_on_small_stack(input: String) -> usize {
    std::thread::Builder::new()
        .stack_size(STACK)
        .spawn(move || {
            let out = elkrs::create_elk().layout_json(&input).expect("layout");
            out["children"].as_array().map_or(0, Vec::len)
        })
        .expect("spawn")
        .join()
        .expect("layout thread panicked")
}

const N: usize = 10_000;

#[test]
fn long_chain_depth_first_cycle_breaking() {
    let input = chain(N, false, large_scope_options("DEPTH_FIRST"));
    assert_eq!(layout_on_small_stack(input), N);
}

#[test]
fn long_cycle_depth_first_cycle_breaking() {
    let input = chain(N, true, large_scope_options("DEPTH_FIRST"));
    assert_eq!(layout_on_small_stack(input), N);
}

#[test]
fn long_cycle_model_order_cycle_breaking() {
    let input = chain(N, true, large_scope_options("DFS_NODE_ORDER"));
    assert_eq!(layout_on_small_stack(input), N);
}

#[test]
fn long_chain_default_options() {
    let input = chain(N, false, json!({"elk.algorithm": "layered"}));
    assert_eq!(layout_on_small_stack(input), N);
}

#[test]
fn long_chain_coffman_graham_layering() {
    let input = chain(
        N,
        false,
        json!({
            "elk.algorithm": "layered",
            "elk.layered.layering.strategy": "COFFMAN_GRAHAM"
        }),
    );
    assert_eq!(layout_on_small_stack(input), N);
}

/// Network simplex on its own, so its tree walks (`tight_tree_dfs`,
/// `postorder_traversal`, the component `dfs`) see a path deep enough to
/// overflow when they recurse, with no layout around it. A bare chain would
/// not do: its leaves are peeled off before the tree is built. The extra
/// first-to-last edge leaves no leaf, so the spanning tree is the whole
/// chain.
#[test]
fn network_simplex_long_chain() {
    use elkrs::alg_common::networksimplex::{NGraph, NNodeId, NetworkSimplex};
    let n = 100_000;
    let layers = std::thread::Builder::new()
        .stack_size(STACK)
        .spawn(move || {
            let mut graph = NGraph::new();
            let ids: Vec<NNodeId> = (0..n).map(|_| graph.add_node()).collect();
            for i in 0..n - 1 {
                graph.add_edge(ids[i], ids[i + 1], 1.0, 1);
            }
            graph.add_edge(ids[0], ids[n - 1], 1.0, 1);
            NetworkSimplex::for_graph(&mut graph).execute();
            ids.iter().map(|&v| graph.node(v).layer).collect::<Vec<_>>()
        })
        .expect("spawn")
        .join()
        .expect("network simplex thread panicked");
    let base = layers[0];
    let relative: Vec<i32> = layers.iter().map(|l| l - base).collect();
    assert!(
        relative.iter().copied().eq(0..n as i32),
        "chain not layered one layer per node"
    );
}

// The same walks with component splitting off, so the cycle breakers and
// layerers see the long chain first rather than the component splitter.

fn unsplit(mut options: Value) -> Value {
    options["elk.separateConnectedComponents"] = json!(false);
    options
}

#[test]
fn unsplit_long_cycle_depth_first_cycle_breaking() {
    let input = chain(N, true, unsplit(large_scope_options("DEPTH_FIRST")));
    assert_eq!(layout_on_small_stack(input), N);
}

#[test]
fn unsplit_long_cycle_model_order_cycle_breaking() {
    let input = chain(N, true, unsplit(large_scope_options("DFS_NODE_ORDER")));
    assert_eq!(layout_on_small_stack(input), N);
}

#[test]
fn unsplit_long_chain_network_simplex_layering() {
    let input = chain(N, false, unsplit(large_scope_options("GREEDY")));
    assert_eq!(layout_on_small_stack(input), N);
}

#[test]
fn unsplit_long_chain_coffman_graham_layering() {
    let input = chain(
        N,
        false,
        unsplit(json!({
            "elk.algorithm": "layered",
            "elk.layered.cycleBreaking.strategy": "GREEDY",
            "elk.layered.layering.strategy": "COFFMAN_GRAHAM"
        })),
    );
    assert_eq!(layout_on_small_stack(input), N);
}
