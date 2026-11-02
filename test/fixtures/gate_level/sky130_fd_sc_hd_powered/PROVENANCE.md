# A powered gate-level netlist on sky130_fd_sc_hd: provenance

`powered.v` is a three-cell structural netlist in the shape a place-and-route
tool writes: each instance of the SkyWater sky130_fd_sc_hd standard cells
(typical corner, the library in `test/fixtures/liberty/pdk/sky130_fd_sc_hd/`)
has its supply pins wired, `VPWR` and `VPB` to the `VPWR` port, `VGND` and
`VNB` to the `VGND` port. One pin is left out on purpose: `u_aoi` has no `VNB`
connection.

| Instance | Cell | Symbol | Supply pins wired |
|---|---|---|---|
| `u_nand` | `sky130_fd_sc_hd__nand2_1` | NAND gate | `VPWR`, `VGND`, `VPB`, `VNB` |
| `u_aoi` | `sky130_fd_sc_hd__a21oi_1` | box (AND-OR-invert) | `VPWR`, `VGND`, `VPB`; `VNB` unconnected |
| `u_ff` | `sky130_fd_sc_hd__dfxtp_1` | flip-flop | `VPWR`, `VGND`, `VPB`, `VNB` |

## How it was made

- **Tool:** none. Written by hand from the sky130_fd_sc_hd pin lists in the
  Liberty file above; no tool output is involved.
- **Date:** 2026-11-02.
- **License:** this repository's own fixture (SPDX: `Apache-2.0`); the cells
  it instantiates are described by the sky130_fd_sc_hd library, Apache-2.0,
  whose provenance and licence are in `test/fixtures/liberty/pdk/sky130_fd_sc_hd/`.

The expectations come from the netlist text itself: which pins each instance
connects, and the power and ground pins each cell's `pg_pin` groups name.

## What reads it

- `test/integration/liberty_gate_level_corpus_test.dart`: a scope that
  connects supply pins draws every one of them, the unconnected `VNB` of
  `u_aoi` included, on the face its `pg_type` names, in the schematic graph,
  the ELK input and both layout engines.
- `test/features/viewer/rendering/liberty_gate_level_golden_test.dart`: the
  render golden `goldens/liberty_powered_sky130.png`, recorded on the CI
  renderer.
