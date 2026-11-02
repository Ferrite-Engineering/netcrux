# sky130_fd_sc_hd, typical corner: provenance

The SkyWater SKY130 high-density standard cells, as Liberty, unchanged
except for gzip compression. Read by
`test/services/liberty/liberty_symbol_corpus_test.dart` and, through the
netlists synthesized from it, `test/integration/liberty_gate_level_corpus_test.dart`.

## Upstream

- **Library:** sky130_fd_sc_hd, corner `tt_025C_1v80` (typical process,
  25 °C, 1.80 V), 428 cells.
- **Repository:** https://github.com/efabless/skywater-pdk-libs-sky130_fd_sc_hd
  (the Efabless fork of https://github.com/google/skywater-pdk-libs-sky130_fd_sc_hd,
  which carries the generated `.lib` files; the Google repository holds only
  their JSON sources).
- **Commit:** `5a42fd01a0eeb2338340438443c7062e198d97a4` (`master`,
  2024-12-11).
- **File:** `timing/sky130_fd_sc_hd__tt_025C_1v80.lib`, 12,841,637 bytes,
  sha256 `8e78e14442062dba34d414fca6490b2f6b96038d4510d1438ca44fee31487135`.
- **License:** Apache License 2.0 (SPDX: `Apache-2.0`), checked against the
  `LICENSE` file at that commit, copied here unchanged as `LICENSE`.
  Copyright SkyWater PDK Authors.

## Download and compression

```sh
curl -fsSL -o sky130_fd_sc_hd__tt_025C_1v80.lib \
  https://raw.githubusercontent.com/efabless/skywater-pdk-libs-sky130_fd_sc_hd/5a42fd01a0eeb2338340438443c7062e198d97a4/timing/sky130_fd_sc_hd__tt_025C_1v80.lib
curl -fsSL -o LICENSE \
  https://raw.githubusercontent.com/efabless/skywater-pdk-libs-sky130_fd_sc_hd/5a42fd01a0eeb2338340438443c7062e198d97a4/LICENSE
gzip -n -9 sky130_fd_sc_hd__tt_025C_1v80.lib
```

The full library is kept, timing and power tables included (2.2 MB
compressed): the reader under test skips those tables, so they are part of
what it is tested on.

## Expected symbols

`sky130_fd_sc_hd__tt_025C_1v80.expected_symbols.json` is written by the
independent oracle one directory up, never by NetCrux:

```sh
python3 -I ../liberty_oracle.py --write sky130_fd_sc_hd__tt_025C_1v80.lib.gz
python3 -I ../liberty_oracle.py --names sky130 sky130_fd_sc_hd__tt_025C_1v80.lib.gz
```

The second command lists the cells whose names suggest a different symbol
from their function; each is decided in `../REVIEW.md`. Of the 428 cells, 184
are drawn as gates: 42 buffers, 21 inverters, 11 AND, 10 NAND, 11 OR, 10 NOR,
6 XOR, 6 XNOR, 4 two-input multiplexers, 45 flip-flops and 18 latches.

Written 2026-11-02 with Python 3.14.
