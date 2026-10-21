# Vendored: elkrs

Upstream: https://github.com/depetrol/elkrs · commit `2651159` (crates.io 0.1.1,
2026-06-17), copied verbatim except for the upstream `.git` directory and the
downloaded `elk/` source tree its README describes.

Why vendored rather than a registry dependency: the port has one author and a
handful of commits, and NetCrux's schematic quality rides on it. Carrying the
source, its 201-case golden corpus, the Java oracle and the differential
fuzzer means every ELK upgrade or local patch can be proved byte-exact here,
without waiting on upstream.

Licence: the crate is labelled Apache-2.0; it is a translation of Eclipse
Layout Kernel source, which is EPL-2.0. NetCrux treats the vendored tree as
EPL-2.0, the licence it already accepts for the vendored elkjs, and records
both in `NOTICES`. Any change to files under `src/` must stay in this tree,
which is public with the open core.

## Local changes

Carried here since 2026-10-21 and offered upstream as three stacked branches
on https://github.com/Ferrite-Engineering/elkrs, each on the one before:
`netlist-corpus` (`ac1351b`), `explicit-stacks` (`27df83f`) and
`wasm-seed-ci` (`1c0f2c1`). This tree is upstream `2651159` plus those three
commits, file for file, except that the fork's `.github/workflows/wasm.yml`
is not copied here (NetCrux's own CI runs the same steps), plus change 4
below, which is carried here only so far. To see the first three, check out
the fork and run `git diff 2651159 wasm-seed-ci`. When upstream merges them,
re-vendor from upstream and delete this section.

1. **Real-netlist corpus and benches.** `goldens/netlists/` holds four
   schematic scopes NetCrux lays out (PicoRV32, ISC; VexRiscv and its two
   caches, MIT) as ELK JSON, with the geometry elkjs 0.9.3 produces for each
   as the expectation; `goldens/netlists/PROVENANCE.md` records sources,
   licences and commands. `tests/netlist_corpus.rs` checks every coordinate
   exactly, `benches/netlist_layout.rs` times them (criterion), and
   `tools/elkjs_layout.js` and `tools/netlist_geometry.py` regenerate the
   expectations. Adds dev-dependencies `flate2` and `criterion` only.
2. **Explicit stacks instead of per-node recursion** in
   `src/alg_layered/components.rs`, `src/alg_layered/p1cycles/depth_first.rs`,
   `src/alg_layered/p1cycles/dfs_node_order.rs`,
   `src/alg_layered/p2layers/network_simplex.rs`,
   `src/alg_layered/p2layers/coffman_graham.rs` and
   `src/alg_common/networksimplex.rs` (`dfs`, `tight_tree_dfs`,
   `postorder_traversal`). Visit order is unchanged: the 201 goldens and the
   netlist corpus pass, the corpus output is byte-identical to `2651159`, and
   so is the output for 5,000 random graphs across the cycle-breaking,
   layering and node-placement strategies. `tests/deep_graphs.rs` lays out
   10,000-node chains on a 1 MiB thread, which overflowed before. This is
   what let `native/elk_ffi` drop its 256 MiB layout thread.
3. **wasm32-unknown-unknown.** `src/alg_force/provider.rs` uses the fixed
   seed 1 for `randomSeed=0` on that target, where `SystemTime::now` panics.
   `tests/wasm.rs` runs goldens, a corpus case, that seed and a 10,000-node
   chain under Node (`wasm-pack test --node --release native/vendor/elkrs
   --test wasm`), and the NetCrux CI `rust` job runs it. Adds the wasm32-only
   dev-dependency `wasm-bindgen-test`.
4. **Two more walks on explicit stacks**, found when the crate ran as
   WebAssembly in a browser Web Worker (NetCrux's `native/elk_wasm`), where
   the engine's stack is far tighter than a native thread's:
   `HyperedgeDummyMerger`'s port walk (`dfs` in
   `src/alg_layered/processors/hyperedge_dummy_merger.rs`) and
   Brandes-Koepf's `place_block` (`src/alg_layered/p4nodes/bk_compactor.rs`,
   now a stack of suspended block walks that resume in the recursive
   order). The 201 goldens and the netlist corpus pass, and the output for
   the corpus and NetCrux's own parity scopes is byte-identical to the tree
   before this change. `tests/deep_graphs.rs` gains
   `netlist_corpus_on_a_tight_stack`, the corpus on a 128 KiB thread, which
   overflowed before. Not yet offered upstream; it belongs on top of
   `wasm-seed-ci`.
