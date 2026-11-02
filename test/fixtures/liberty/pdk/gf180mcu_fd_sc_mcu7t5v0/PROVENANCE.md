# gf180mcu_fd_sc_mcu7t5v0, typical corner: provenance

The GlobalFoundries 180MCU 7-track, 5 V standard cells, as Liberty,
unchanged except for gzip compression. Read by
`test/services/liberty/liberty_symbol_corpus_test.dart`.

## Upstream

- **Library:** gf180mcu_fd_sc_mcu7t5v0, corner `tt_025C_5v00` (typical
  process, 25 °C, 5.00 V), 229 cells.
- **Source repository:** https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu7t5v0,
  commit `43beb45e4d323a76239de436db2df6732e9a689b` (`main`). It keeps one
  Liberty file per cell and corner under `cells/`; the library as one file
  is assembled by open_pdks.
- **Assembled file:** the open_pdks build at commit
  `54435919abffb937387ec956209f9cf5fd2dfbee`, as published by the ciel PDK
  manager: release `gf180mcu-54435919abffb937387ec956209f9cf5fd2dfbee` of
  https://github.com/fossi-foundation/ciel-releases, asset
  `gf180mcu_fd_sc_mcu7t5v0.tar.zst` (sha256
  `dcacb088f91d71a399a733e0cda749aa5ad3c7ec41d15b2cc32856d39cdbe678`), path
  `gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lib/gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib`
  inside it, 20,122,761 bytes, sha256
  `330aa9439255e3870ad7adfb987cd4d7bcfa7b6f9fb0cd0a712400e9bd80e38a`.
- **License:** Apache License 2.0 (SPDX: `Apache-2.0`), checked against the
  `LICENSE` file of the source repository at that commit, copied here
  unchanged as `LICENSE`; the file's own header carries the same notice.
  Copyright 2022 GlobalFoundries PDK Authors.

## Download and compression

```sh
curl -fsSL -O \
  https://github.com/fossi-foundation/ciel-releases/releases/download/gf180mcu-54435919abffb937387ec956209f9cf5fd2dfbee/gf180mcu_fd_sc_mcu7t5v0.tar.zst
tar -xf gf180mcu_fd_sc_mcu7t5v0.tar.zst \
  gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lib/gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib
curl -fsSL -o LICENSE \
  https://raw.githubusercontent.com/google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu7t5v0/43beb45e4d323a76239de436db2df6732e9a689b/LICENSE
gzip -n -9 gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib
```

The full library is kept, timing and power tables included (2.8 MB
compressed).

## Expected symbols

`gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.expected_symbols.json` is written by
the independent oracle one directory up, never by NetCrux:

```sh
python3 -I ../liberty_oracle.py --write gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib.gz
python3 -I ../liberty_oracle.py --names gf180mcu gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib.gz
```

Of the 229 cells, 143 are drawn as gates: 28 buffers, 16 inverters, 9 AND,
9 NAND, 9 OR, 9 NOR, 6 XOR, 6 XNOR, 3 two-input multiplexers, 36 flip-flops
and 12 latches. `../REVIEW.md` records the cells whose names and functions
disagree.

Written 2026-11-02 with Python 3.14.
