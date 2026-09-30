# picorv32 — captured fixture provenance

A real, permissively-licensed RISC-V core, committed in **two forms** of the
**same upstream revision** so it serves two jobs:

- **`picorv32.v`** — the genuine RTL **source**, for opening in NetCrux (File →
  Open Source Files… / `netcrux picorv32.v`) to exercise live Yosys elaboration
  + hierarchy + schematic layout/render at real scale (~1600 cells). This is the
  "large real design" rendering/perf fixture.
- **`picorv32.netlist.json.gz`** — the pre-elaborated Yosys netlist, so the
  parser golden sweep (`test/services/yosys/netlist_golden_test.dart`) exercises
  `StreamingYosysJsonReader` against genuine synthesis output (not just
  hand-synthesized chains), Yosys-free.

Both are the same design at the same revision: elaborating the committed
`picorv32.v` with the command below reproduces the committed netlist's
**1599-cell** `picorv32` module exactly.

## Upstream

- **Source project:** PicoRV32 — a size-optimized RV32IMC CPU core.
- **Upstream:** https://github.com/YosysHQ/picorv32 (`picorv32.v`).
- **Pinned commit:** `87c89acc18994c8cf9a2311e871818e87d304568`.
- **License:** ISC (SPDX: `ISC`) — on the suite allow-list. Copyright (C) 2015
  Claire Xenia Wolf. The ISC permission + warranty-disclaimer notice is retained
  verbatim in the header of the committed `picorv32.v`; do not strip it.

## `picorv32.v` (source)

- **Acquired:** `curl -L https://raw.githubusercontent.com/YosysHQ/picorv32/87c89acc18994c8cf9a2311e871818e87d304568/picorv32.v`
- **sha256:** `0836050971b3c6cdd28ac3b1e5719a67fb645161912bef1e472e63995ceb0622`
- **Modules:** `picorv32` (core), `picorv32_regs`, `picorv32_pcpi_mul`,
  `picorv32_pcpi_fast_mul`, `picorv32_pcpi_div`, `picorv32_axi`,
  `picorv32_axi_adapter`, `picorv32_wb`.
- **Opening it in NetCrux:**
  - **Just open the file** — `netcrux picorv32.v` (or File → Open Source Files…).
    NetCrux's loose-source flow runs `hierarchy -check -auto-top`, which
    auto-selects **`picorv32_wb`** (the Wishbone SoC wrapper — the only
    un-instantiated module) as the top. You get the full hierarchy
    `picorv32_wb → picorv32_axi → picorv32 (+ adapter)`; click into the
    **`picorv32`** scope in the left pane to render the dense ~1599-cell core.
    Flattened, `picorv32_wb` is ~1660 cells.
  - **Open straight to the dense core** — pin the top via a one-off
    `.netcrux-project` (NetCrux reads `sourceFiles` verbatim, so use an absolute
    path):
    ```json
    {
      "version": 1,
      "sourceFiles": ["/ABSOLUTE/PATH/TO/picorv32.v"],
      "topModule": "picorv32"
    }
    ```
    Open it via File → Open Project. Renders the 1599-cell `picorv32` module
    directly.
- **Requires:** Yosys on PATH. (No ghdl plugin needed — Verilog only.)

## `picorv32.netlist.json.gz` (pre-elaborated netlist)

- **Acquisition:** elaborate the committed `picorv32.v` with Yosys, then gzip:

  ```sh
  yosys -q -p "read_verilog picorv32.v; hierarchy -check -top picorv32; \
    proc; write_json picorv32.netlist.json"
  gzip picorv32.netlist.json   # committed as picorv32.netlist.json.gz
  ```

- **Yosys:** 0.66. Re-elaboration with a newer Yosys may shift the structural
  fingerprint; refresh the golden with
  `REGENERATE=1 flutter test test/services/yosys/netlist_golden_test.dart`.
- **Shape:** 1 module (`picorv32`), 1599 cells, 27 ports, ~3096 nets;
  Yosys-internal cell types (`$mux`, `$eq`, `$dff`, `$pmux`, `$add`, …).
