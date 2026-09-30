# mesh_1m (on-demand)

A 1000000-cell mesh — the ingestion-memory perf target. The
~several-hundred-MB netlist is **not committed**; only the manifest
(`mesh_1m.gen.json`) is. Build it on demand:

```sh
dart run tool/generate_netlist_fixtures.dart --design mesh_1m --out build/perf/mesh_1m.json
```
