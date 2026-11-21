# ROHD netlist fixtures

Netlists written by ROHD's `NetlistSynthesizer`, the Yosys JSON superset
that ROHD (the hardware framework written in Dart) exports. They are the
input of `test/services/yosys/rohd_netlist_extensions_test.dart`.

| File | Top module | What it exercises |
|------|-----------|-------------------|
| `sample_pipeline.json` | `SamplePipeline` | a structure on the input and output ports, `$struct_unpack` and `$struct_pack` cells, a `Sequential` and a `Combinational` block |
| `lane_reducer.json` | `LaneReducer` | array input and output ports, array concat and slice cells |
| `demo_top.json` | `DemoTop` | three levels of hierarchy, a nested structure, an array, a state machine, sub-module instances |
| `hcl_fifo.json` | `Fifo_D4_W8` | a component from the ROHD Hardware Component Library, a design this repository did not write |

Every file is written with source tracing on: it carries the top-level
`files` array and a `rohd.src_trace` attribute on each module.

## Regenerating

```bash
cd test/fixtures/netlist/rohd/generated/generator
dart pub get
dart run bin/generate.dart
```

`generator/` is a separate Dart package (it is excluded from this
repository's analysis) so that ROHD never enters NetCrux's own dependency
graph. The designs are in `generator/lib/designs.dart`; the source locations
in the fixtures are lines of that file, and a test reads the line each one
names, so a change to `designs.dart` means regenerating all four files.

## Provenance

- **Regenerated:** 2026-11-20.
- **ROHD:** the released package `rohd` 0.7.4 from pub.dev (the generator
  asks for `^0.7.3`), netlist format version `0.1.0`, the same format as the
  pre-release commit the fixtures were first made with. The format is
  described in `doc/netlist_json_format.md` of https://github.com/intel/rohd.
- **ROHD-HCL:** https://github.com/intel/rohd-hcl at commit
  `767d395261668ba9f5cd3c127f7a027093ed2032` (package version 0.3.2, which
  depends on `rohd ^0.7.3`; no tag after v0.3.2 builds against released ROHD).
  It is used for `hcl_fifo.json` only.
- **Changes against the previous fixtures (ROHD main at `2d84f73`, ROHD-HCL at
  `3a3fab3`):** the `files` paths now point into the hosted pub cache; the
  source-trace line numbers moved with the ROHD sources; ROHD renamed its
  `Swizzle` to `Concat`, so the cells and nets named after it are now
  `concat...` and `..._concatd` (their `$concat` type is unchanged); one
  `$struct_unpack` cell in `demo_top.json` swapped places with another and
  the net numbers after it shifted; `hcl_fifo.json` is larger because
  ROHD-HCL's `Fifo` and `RegisterFile` changed between 3a3fab3 and 767d395.
  The module names are the same.
- **License:** both are BSD-3-Clause, Copyright (C) Intel Corporation. The
  netlists carry structure derived from ROHD's and ROHD-HCL's own source
  (the source-trace entries name their files), so the notice is reproduced
  here.

The generator edits two things in what ROHD writes, so that the committed
files do not depend on the machine that made them: the `files` entries are
normalised (a path inside the generator package is made relative to this
directory; the location of the pub cache becomes `/pub-cache`). Nothing else
is touched.

## License notice

```
BSD 3-Clause License

Copyright (C) 2021-2026 Intel Corporation

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
