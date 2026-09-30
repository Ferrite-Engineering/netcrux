# Netlist fixture corpus

The large-netlist stress ladder for the Yosys-free golden sweep
(`test/services/yosys/netlist_golden_test.dart`) and the ingestion bench
(`test/perf/ingest_bench_test.dart`).

## Layout

Each design lives at `<design>/generated/` and carries a triple:

| File | Role |
|------|------|
| `<design>.v` | human-readable RTL (informational) |
| `<design>.netlist.json` *or* `.netlist.json.gz` | deterministic Yosys-shaped JSON the parser ingests **without spawning Yosys** |
| `<design>.expected_netlist.json` | the `NetlistGolden` the parser produces (counts + cell-type histogram + FNV-1a fingerprint) |

| Design | Cells | Shape | Committed as |
|--------|-------|-------|--------------|
| `chain_1k` | 1 000 | 1 × 1000 `$_DFF_P_` pipeline | raw `.netlist.json` |
| `chain_10k` | 10 000 | 1 × 10000 pipeline (interactive-viewing target) | gzip `.netlist.json.gz` |
| `grid_100k` | 100 000 | 100 × 1000 (COI / X-trace scale) | gzip `.netlist.json.gz` |
| `mesh_1m` | 1 000 000 | 1000 × 1000 (ingestion-memory target) | **not committed** — manifest only |

The `malformed/` sibling directory is the malformed-input adversarial corpus (exempt from
the golden sweep). `mesh_1m` is built on demand by the bench, never committed.

## Regenerate

```sh
# Commit-time corpus (chain_1k / chain_10k / grid_100k + the mesh manifest):
dart run tool/generate_netlist_fixtures.dart --tier committed

# On-demand 1M-cell mesh for the ingestion-memory bench (NOT committed):
dart run tool/generate_netlist_fixtures.dart --design mesh_1m --out build/perf/mesh_1m.json

# Refresh the goldens against the live parser only:
REGENERATE=1 flutter test test/services/yosys/netlist_golden_test.dart
```

## Notes

- The committed JSON is **hand-synthesized** (deterministic `$_DFF_P_`
  chains/grids), not the output of a real Yosys run, so the golden sweep is
  Yosys-free and environment-independent.
- Compression is **gzip** (`dart:io`), not zstd, to avoid a native zstd dependency. The golden test and bench read
  `.gz` transparently.
- This generator supersedes `tool/generate_large_chain_fixture.dart` for the
  stress ladder; that older 32-cell `large_chain` fixture is retained only
  because `test/property/netlist_round_trip_test.dart` still consumes it.
