# IHP sg13g2_stdcell, typical corner: provenance

The IHP SG13G2 130 nm BiCMOS open PDK's standard cells, as Liberty,
unchanged except for gzip compression. Read by
`test/services/liberty/liberty_symbol_corpus_test.dart`.

## Upstream

- **Library:** sg13g2_stdcell, corner `typ_1p20V_25C` (typical process,
  1.20 V, 25 °C), 84 cells. The Liberty file declares no `pg_pin`, so no
  cell has a supply pin to place.
- **Repository:** https://github.com/IHP-GmbH/IHP-Open-PDK
- **Commit:** `5e6d592e4002946a4616f798c357f0f3c06cf3b6` (`main`,
  2026-09-01).
- **File:** `ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib`,
  1,720,231 bytes, sha256
  `7677a8918689f452e80405ad16a83e744709342574f2aedcc507c2758986b396`.
- **License:** Apache License 2.0 (SPDX: `Apache-2.0`), checked against the
  repository's `LICENSE` at that commit, copied here unchanged as `LICENSE`;
  the file's own header carries the same notice. Copyright 2024 IHP PDK
  Authors.

## Download and compression

```sh
curl -fsSL -o sg13g2_stdcell_typ_1p20V_25C.lib \
  https://raw.githubusercontent.com/IHP-GmbH/IHP-Open-PDK/5e6d592e4002946a4616f798c357f0f3c06cf3b6/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
curl -fsSL -o LICENSE \
  https://raw.githubusercontent.com/IHP-GmbH/IHP-Open-PDK/5e6d592e4002946a4616f798c357f0f3c06cf3b6/LICENSE
gzip -n -9 sg13g2_stdcell_typ_1p20V_25C.lib
```

The full library is kept, timing and power tables included (0.3 MB
compressed).

## Expected symbols

`sg13g2_stdcell_typ_1p20V_25C.expected_symbols.json` is written by the
independent oracle one directory up, never by NetCrux:

```sh
python3 -I ../liberty_oracle.py --write sg13g2_stdcell_typ_1p20V_25C.lib.gz
python3 -I ../liberty_oracle.py --names sg13g2 sg13g2_stdcell_typ_1p20V_25C.lib.gz
```

Of the 84 cells, 53 are drawn as gates: 8 buffers, 5 inverters, 6 AND,
4 NAND, 6 OR, 6 NOR, 1 XOR, 1 XNOR, 2 two-input multiplexers, 9 flip-flops
and 5 latches. Every cell's name agrees with its function.

Written 2026-11-02 with Python 3.14.
