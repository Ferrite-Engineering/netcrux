# Gate-level netlists synthesized to sky130_fd_sc_hd: provenance

Two RTL fixtures of this repository, `test/fixtures/verilog/cdc_capture.v`
and `test/fixtures/verilog/adder4.v`, synthesized to the SkyWater
sky130_fd_sc_hd standard cells (typical corner, the library in
`test/fixtures/liberty/pdk/sky130_fd_sc_hd/`), each written twice by the same
Yosys run: as structural Verilog for the native gate-level reader, and as
Yosys JSON for File > Open Netlist JSON.

| Design | Cells | Cell types | Symbols the oracle gives them |
|---|---|---|---|
| `cdc_capture` | 70 | 17 | flip-flop (`dfrtp_1`, 28), two-input multiplexer, AND, NAND, NOR, XOR, XNOR, inverter, and boxes (`a21oi_1`, `nand2b_1`, `nor4bb_1`) |
| `adder4` | 12 | 2 | XNOR (`xnor2_1`) and box (`maj3_1`) |

## How they were made

- **Tool:** Yosys 0.70+post (git sha1 `0c11ea098be065e585a90a06e7b7da49936cf231`),
  Homebrew build on macOS, using its bundled ABC.
- **Script:** `run.ys` in this directory, run from it:

  ```sh
  yosys -q -s run.ys
  ```

  For each design: `read_liberty -lib` (the cells as black boxes), the RTL,
  `synth -flatten`, `dfflibmap -liberty` (flip-flops only in
  `cdc_capture`), `abc -liberty`, `opt_clean -purge`, `rename -enumerate` so
  the Verilog and the JSON name instances and nets alike, `write_verilog
  -noattr`, then the unused library black boxes deleted and `write_json`.
- **Date:** 2026-11-02.
- **License:** the designs are this repository's own fixtures (SPDX:
  `Apache-2.0`); the cells they instantiate are described by the
  sky130_fd_sc_hd library, Apache-2.0, whose provenance and licence are in
  `test/fixtures/liberty/pdk/sky130_fd_sc_hd/`.

A newer ABC may map the same RTL to different cells. The tests compare the
two forms with each other and with the oracle's expected symbols for each
cell type, never with a list of instances, so a regenerated pair needs no
other change as long as both files come from the same run.

## What reads them

- `test/integration/liberty_gate_level_corpus_test.dart`: both forms, the
  symbol of every instance against
  `sky130_fd_sc_hd__tt_025C_1v80.expected_symbols.json`, signal-pin faces in
  the ELK input and in both layout engines, supply pins, the data sheet and
  the module area.
- `test/integration/native_vs_yosys_test.dart`: the Verilog through the
  native reader and through the Yosys route of the app, model against model.

The Yosys JSON has no supply pins: `read_liberty -lib` keeps no `pg_pin` in a
cell's black box. The native reader, like the app's own Yosys route, declares
each `pg_pin` the library lists, but neither route draws them: no instance of
a synthesized netlist connects a supply pin, and a scope that connects none
draws none of the unconnected ones. The powered counterpart, where every
supply pin is drawn, is `test/fixtures/gate_level/sky130_fd_sc_hd_powered/`.
