# Review of the expected symbols

`liberty_oracle.py` decides each cell's symbol from its Liberty description,
following `docs-site/docs/files-and-projects.md` (section "Standard cells as
gate symbols"). As a cross-check that shares nothing with that decision,
`liberty_oracle.py --names <pdk>` also guesses each cell's symbol from the
PDK's naming convention (`nand2` a NAND, `dfxtp` a flip-flop, `dlx` a latch,
`a21oi` a box, and so on) and lists every cell where the two differ. Each
such cell was decided by reading its Liberty text; the decisions are below.
In every case the function is what the cell computes and the expected file
keeps the oracle's answer from it.

## Cells whose name and function disagree

| Library | Cells | Name suggests | Function says | What the Liberty text shows | Expected |
|---|---|---|---|---|---|
| sky130_fd_sc_hd | `lpflow_clkbufkapwr_{1,2,4,8,16}` | box (the `lpflow_` prefix and `kapwr` suffix match no rule) | buffer | `X : "(A)"`, one input `A`; an always-on clock buffer whose extra `KAPWR` pin is `pg_type : backup_power` | buffer, `KAPWR` on top with `VPWR` and `VPB` |
| sky130_fd_sc_hd | `lpflow_clkinvkapwr_{1,2,4,8,16}` | box | inverter | `Y : "(!A)"`, one input `A`; `KAPWR` is `backup_power` | inverter, `KAPWR` on top |
| sky130_fd_sc_hd | `lpflow_inputiso0n_1` | box (an isolation cell by name) | and | `X : "(SLEEP_B&A)"`, inputs `A` and `SLEEP_B` | and: the cell is a two-input AND whose second input is the isolation enable |
| sky130_fd_sc_hd | `lpflow_inputiso1p_1` | box | or | `X : "(A) \| (SLEEP)"` | or |
| sky130_fd_sc_hd | `lpflow_inputisolatch_1` | box | latch | `latch ("IQ","IQ_N") { data_in : "D"; enable : "SLEEP_B"; }`, `Q : "IQ"`; `SLEEP_B` is marked `clock : "true"` | latch, with no clock wedge (only flip-flops have wedges) |
| sky130_fd_sc_hd | `lpflow_lsbuf_lh_hl_isowell_tap_{1,2,4}`, `lpflow_lsbuf_lh_isowell_4`, `lpflow_lsbuf_lh_isowell_tap_{1,2,4}` | box (a level shifter by name) | buffer | `X : "(A)"`, one input `A`; a second supply `VPWRIN` (or `LOWLVPWR`) with `pg_type : primary_power` | buffer, both supplies on top |
| sky130_fd_sc_hd | `probec_p_8` | box (`probec_p` matches no rule, unlike `probe_p`) | buffer | `X : "(A)"`, one input `A` | buffer |
| asap7sc7p5t (INVBUF) | `CKINVDCx{5p33,6p67,8,9p33,10,11,12,14,16,20}_ASAP7_75t_R` | box (`CKINVDC` matches no rule) | inverter | `Y : "!A"`, one input `A`; `area` written without its semicolon | inverter |

IHP sg13g2_stdcell has no disagreement. gf180mcu_fd_sc_mcu7t5v0 has none
with the rules as they stand; the two it had are under "Changes to the
oracle".

## Cells the documentation leaves open, decided here

These follow the documentation as it now reads; the edge-case library
(`../edge_cases.lib`) has one cell for each.

| Case | Decision | Example in the PDKs |
|---|---|---|
| A latch whose enable pin is marked `clock : true` | latch, no clock wedge | sky130 `lpflow_inputisolatch_1`, `dlxtp_1` |
| An integrated clock gate (`clock_gating_integrated_cell`; sky130 and gf180 describe it with a `statetable` and a `state_function` output) | box | sky130 `dlclkp`, `sdlclkp`; gf180 `icgtp`, `icgtn`; IHP `lgcp`, `slgcp`; ASAP7 `ICGx` |
| A tri-state output | box, even when the function reads every input | sky130 `ebufn`, `einvn`, `einvp`; gf180 `bufz`, `invz`; IHP `ebufn`, `einvn` |
| A tie cell (outputs only, constant functions) | box, its supply pins placed | sky130 `conb_1`; gf180 `tieh`, `tiel`; IHP `tiehi`, `tielo`; ASAP7 `TIEHIx1`, `TIELOx1` |
| A `pg_pin` named in lower case, or `VDD…` / `VSS…` with a suffix | placed by name, without regard to case | none in these four libraries |

## Changes to the oracle

Made while the corpus was built, each after reading the cells concerned.
None changed a symbol the oracle derives from a function; all were in the
naming rules of the cross-check.

1. `sedfxbp`, `sedfxtp` (sky130 scan flip-flops with enable) were not
   recognised as flip-flop names; the rule now reads an optional `s` and
   `e` before `df`.
2. gf180 `dlya` to `dlyd` (delay buffers) were read as latches by the `dl`
   rule; the buffer rule now takes every `dly` name.
3. Integrated clock gates (`dlclkp`, `icg…`, `lgcp`) were read as latches or
   flip-flops by name; a rule placed first now names them boxes, matching
   their descriptions (sky130 `dlclkp` and gf180 `icgtn` read: a
   `statetable` and an output with only a `state_function`).

## Finding against NetCrux

The edge case `ec_tristate_function_of_all_inputs` (an output with
`three_state : "!EN"` and `function : "A&EN"`) was drawn as an AND gate,
although the documentation says a cell with a tri-state enable keeps its
box. No cell of the four libraries has that shape (their tri-state cells
leave the enable out of the function, which already made them boxes), so
the PDK corpus passed and only the hand-written case caught it.
`LibertyParser` now keeps which pins have a `three_state` attribute
(`LibertyCell.threeStatePins`, cache format 3) and `libertyCellSymbolFor`
draws any cell with a tri-state output as a box; a unit test in
`test/services/liberty/liberty_cell_index_test.dart` covers it.
