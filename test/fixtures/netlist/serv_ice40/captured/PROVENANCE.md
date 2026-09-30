# serv_ice40 — captured fixture provenance

A real post-synthesis netlist of a real SoC, as an FPGA flow produces it: the
SERV RISC-V core's `servant` reference SoC, synthesized for a Lattice iCE40
with Yosys. Committed for what its shape does to the hierarchy: `synth_ice40`
reads the iCE40 cell library before synthesis, so `write_json` carries all
fifty library modules (`SB_LUT4`, `SB_DFF`, `SB_CARRY`, `SB_RAM40_4K`, …) with
the `blackbox` attribute set, and every one of the top module's 966 cells
instantiates one of them. A hierarchy browser that treats "cell type names a
module" as "child scope" turns each LUT and flop into an empty scope with five
ports and nothing inside; this fixture keeps `Module.isBlackBox` and the
hierarchy walk holding those instances as cells.

Only the netlist is committed: the RTL is SERV's, at the upstream below.

## Upstream

- **Source project:** SERV — the award-winning bit-serial RISC-V core — and
  its `servant` reference SoC.
- **Upstream:** https://github.com/olofk/serv (FuseSoC core
  `award-winning:serv:servant`, version 1.4.0).
- **License:** ISC (SPDX: `ISC`) — on the suite allow-list. Copyright (c)
  Olof Kindgren.

## `serv_ice40.netlist.json.gz` (captured netlist)

- **Produced by:** Yosys 0.33 (git sha1 `2584903a060`), the `synth_ice40`
  flow of the `servant` core's iCE40 target, followed by `write_json`. The
  `creator` field in the document records the Yosys build.
- **Contributed:** by the SERV author while beta-testing NetCrux 1.0, as the
  netlist behind the hierarchy report this fixture guards against.
- **sha256** (of the uncompressed document):
  `b70ef2be46dece8433dde5b7f8fba84468f04a33cc9e63c8f55d09b21312122d`
- **Shape:** 51 modules; top `service` (966 cells: 509 `SB_LUT4`,
  120 `SB_DFFE`, 104 `SB_CARRY`, 99 `SB_DFF`, …; 2 ports); the other 50 are
  black-box library modules, four of them (`SB_RAM40_4K*`) carrying
  `$specify` timing cells of their own.
- **Opening it in NetCrux:** File → Open Netlist JSON… (or `netcrux
  serv_ice40.netlist.json` after `gunzip -k`). The hierarchy shows one scope,
  `service`, and Search (++ctrl+f++) finds cells such as
  `servant.servile.cpu.alu.add_cy_r_SB_LUT4_I3_1`.
