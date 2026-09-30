# VexRiscv — captured source fixture

A real, MIT-licensed, **hierarchical** RISC-V core, committed as RTL source
for opening and rendering in NetCrux. It complements the (flat) `picorv32`
fixture: VexRiscv elaborates to a 3-module hierarchy — `VexRiscv` (the
pipeline) instantiating `DataCache` and `InstructionCache` — so it exercises
the hierarchy browser, per-scope layout, and the multi-scope layout cache at
real scale, not just one dense flat module. The 3-module structure is
verified automatically (Yosys-free) by the golden sweep — see
`vexriscv.netlist.json.gz` below.

This is the **`Full`** configuration (caches + M extension + …). Bigger than
picorv32: ~1 980 cells total.

## Upstream

- **Source project:** VexRiscv — a 32-bit RISC-V CPU implemented in SpinalHDL.
- **Generator:** the committed Verilog is the SpinalHDL-generated `VexRiscv_Full.v`
  from the LiteX data package, which commits pre-generated VexRiscv cores so
  downstreams don't need a Scala/SpinalHDL toolchain.
- **Distribution repo:** https://github.com/litex-hub/pythondata-cpu-vexriscv
  (`pythondata_cpu_vexriscv/verilog/VexRiscv_Full.v`).
- **Pinned commit (distribution):** `642ecfed1c84460555d6d803d660cc60cfc1ecb6`.
- **Generator provenance (from the file header):** SpinalHDL v1.9.4
  (git head `270018552577f3bb8e5339ee2583c9c22d324215`); VexRiscv git hash
  `8542a5786b26857f3ef830ae9e72eec031df42d3`.
- **License:** MIT (SPDX: `MIT`) — on the suite allow-list. Copyright (c) 2016
  Spinal HDL contributors. The MIT permission notice is reproduced below
  because the generated Verilog carries no header notice of its own; it must
  travel with this fixture.

## `vexriscv.v` (source)

- **Acquired:** `curl -L https://raw.githubusercontent.com/litex-hub/pythondata-cpu-vexriscv/642ecfed1c84460555d6d803d660cc60cfc1ecb6/pythondata_cpu_vexriscv/verilog/VexRiscv_Full.v` (committed byte-identical).
- **sha256:** `1ee38dc4b0f3a2ce08de9df1f8e2bb8fceb628a89adb7f624f38ae44cebe9fcc`
- **Modules:** `VexRiscv` (top, ~1 463 cells), `DataCache` (~404 cells),
  `InstructionCache` (~115 cells); ~1 980 cells flattened. Yosys-internal cell
  types (`$mux`, `$dff`, `$eq`, `$add`, `$pmux`, …).
- **Opening it in NetCrux:**
  - `netcrux test/fixtures/netlist/vexriscv/captured/vexriscv.v` (or File →
    Open Source Files…). NetCrux's loose-source flow runs
    `hierarchy -check -auto-top`, which cleanly auto-selects **`VexRiscv`** as
    the top (the only un-instantiated module — no project/top pin needed,
    unlike picorv32). Expand the hierarchy to navigate into the `DataCache` /
    `InstructionCache` scopes; the `VexRiscv` scope is the dense ~1 463-cell
    pipeline.
- **Requires:** Yosys on PATH (Verilog only, no ghdl plugin) — for opening it
  live in NetCrux. The automated test below is Yosys-free.

## `vexriscv.netlist.json.gz` (golden sweep companion)

- Elaborated once via `yosys -q -p "read_verilog vexriscv.v; hierarchy -check
  -auto-top; proc; write_json vexriscv.netlist.json"` (the same auto-top flow
  NetCrux's loose-source open uses), then gzipped.
- Auto-discovered by `test/services/yosys/netlist_golden_test.dart`, the
  same Yosys-free sweep that covers `picorv32`: parses the committed JSON with
  the production `StreamingYosysJsonReader` and diffs a `NetlistGolden`
  against the committed `vexriscv.expected_netlist.json` (per-module cell /
  port / net counts + cell-type histogram for `VexRiscv` / `DataCache` /
  `InstructionCache`). This is what makes the 3-module hierarchy claim above a
  regression-tested fact rather than a doc assertion — no Yosys spawn needed
  in CI.
- Refresh after changing the source: `REGENERATE=1 flutter test
  test/services/yosys/netlist_golden_test.dart`, then re-gzip
  `vexriscv.netlist.json` and delete the uncompressed copy (see
  `test/fixtures/netlist/helpers/README.md`).

## MIT License

```
MIT License

Copyright (c) 2016 Spinal HDL contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
