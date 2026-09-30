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

Local changes: none.
