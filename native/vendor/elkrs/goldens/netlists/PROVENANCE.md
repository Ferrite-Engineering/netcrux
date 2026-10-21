# Real-netlist corpus

Four schematic scopes of two open RISC-V cores, laid out with the option set
a schematic viewer uses, so changes to the crate are tested against graphs
of the size and shape real users lay out, not only the unit-sized goldens.
`tests/netlist_corpus.rs` checks them; `benches/netlist_layout.rs` times
them.

| Case | Cells | Source | Licence |
|---|---|---|---|
| `picorv32` | 1599 | PicoRV32, YosysHQ/picorv32 `87c89acc18994c8cf9a2311e871818e87d304568`, module `picorv32` | ISC |
| `vexriscv_VexRiscv` | ~1460 | VexRiscv `Full`, litex-hub/pythondata-cpu-vexriscv `642ecfed1c84460555d6d803d660cc60cfc1ecb6`, `VexRiscv_Full.v`, module `VexRiscv` | MIT |
| `vexriscv_DataCache` | ~400 | same file, module `DataCache` | MIT |
| `vexriscv_InstructionCache` | ~115 | same file, module `InstructionCache` | MIT |

## Inputs: `cases/<name>.json.gz`

Each input is the ELK JSON NetCrux (github.com/Ferrite-Engineering/netcrux)
builds for one module of a Yosys netlist: `buildElkInput` in
`lib/services/layout/elk_layout_service.dart` at NetCrux commit `cb10715`,
over the netlists NetCrux commits under `test/fixtures/netlist/`
(`yosys -p "read_verilog <file>; hierarchy -check ...; proc; write_json"`).

The option set, which is the point of the corpus:

- root: `elk.algorithm=layered`, `elk.direction=RIGHT`,
  `elk.spacing.nodeNode=20`, `elk.layered.spacing.nodeNodeBetweenLayers=30`;
- above 500 cells (`picorv32`, `vexriscv_VexRiscv`) also
  `elk.layered.thoroughness=1` and
  `elk.layered.cycleBreaking.strategy=DEPTH_FIRST`;
- every cell: `elk.portConstraints=FIXED_SIDE`, inputs on `WEST`, outputs
  on `EAST`, one label;
- nets with more than 32 edges (clocks, resets, enables) left out; every
  other net split into one-source, one-target edges.

## Expectations: `expected/<name>.geometry.json.gz`

The layout elkjs 0.9.3 (the GWT build of the Java Eclipse Layout Kernel)
produces for each input, reduced to geometry by `tools/netlist_geometry.py`.
They do not come from this crate. Produced 2026-10-21 twice, with identical
results: on JavaScriptCore inside NetCrux, and on Node v22.14.0:

```sh
npm install --prefix /tmp/elkjs elkjs@0.9.3
NODE_PATH=/tmp/elkjs/node_modules node tools/elkjs_layout.js \
  goldens/netlists/cases/picorv32.json.gz /tmp/picorv32.layout.json
python3 tools/netlist_geometry.py /tmp/picorv32.layout.json \
  goldens/netlists/expected/picorv32.geometry.json.gz
```

The crate at upstream commit `2651159` matched all four exactly (every
coordinate equal as an f64), and so does every change since.

## Licences

The cases are derived from the netlists of the designs above and carry
their notices.

PicoRV32, ISC:

```
Copyright (C) 2015  Claire Xenia Wolf <claire@yosyshq.com>

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

VexRiscv, MIT:

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
