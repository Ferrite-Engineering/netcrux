# ASAP7 asap7sc7p5t, RVT typical corner: provenance

The ASAP7 7.5-track predictive 7 nm standard cells, regular threshold
voltage, typical corner, as Liberty with the timing and power tables
removed. Read by `test/services/liberty/liberty_symbol_corpus_test.dart`.

## Upstream

- **Library:** asap7sc7p5t, RVT, TT, split by the library into one file per
  cell group. Five are kept here:

  | File | Cells | Original bytes | sha256 of the `.lib.7z` |
  |---|---|---|---|
  | `asap7sc7p5t_AO_RVT_TT_nldm_211120.lib` | 42 | 22,136,706 | `d8ec2c98f0709817cf9bf08ac6bd3363ba086789bdbeb9d1036b3e5b2ea56041` |
  | `asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib` | 37 | 309,886 | `3803bb90380bc39445db17d2f60a2c53bd4baf63ddffbc742ab7ae651dc649e0` |
  | `asap7sc7p5t_OA_RVT_TT_nldm_211120.lib` | 34 | 19,915,253 | `6a5204f97ffc242e999bafedf5de95dc06a49624928f98dbb7b415c9e492e689` |
  | `asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib` | 33 | 1,512,690 | `e2895b3b0b32e4d0aa10e04c465b6297eec5a8eb3615058edc8595faeb094138` |
  | `asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib` | 56 | 2,306,883 | `78c5e55ec239efe080458532f9f55dff5457c3ce4144d8c9f2bac1a484b634c4` |

- **Repository:** https://github.com/The-OpenROAD-Project/asap7sc7p5t_28
- **Commit:** `e5bd25da72cd297b8c0ec6f77600e0cbaa1124d0` (`main`,
  2026-10-17).
- **Files:** `LIB/NLDM/<file>.7z`, each a 7-Zip archive of one `.lib`.
- **License:** BSD 3-Clause License (SPDX: `BSD-3-Clause`), checked against
  the repository's `LICENSE` and `license/LICENSE.lib` at that commit; the
  repository `LICENSE` is copied here unchanged as `LICENSE`, and each of the
  five files keeps the same notice in its own header comment, which the
  trimming below leaves in place. Copyright Lawrence T. Clark, Vinay
  Vashishtha, or Arizona State University.
- **Left out:** `asap7sc7p5t_TBUF_RVT_TT_nldm_260831.lib` (one tri-state
  buffer, added upstream in 2026). Unlike the other five it carries no BSD
  notice of its own, only a note that Cadence waived its terms so the file
  could be made public "for use by researchers", which is not plainly the
  same terms as the repository licence.

## Download, extraction and trimming

```sh
base=https://raw.githubusercontent.com/The-OpenROAD-Project/asap7sc7p5t_28/e5bd25da72cd297b8c0ec6f77600e0cbaa1124d0
for f in AO_RVT_TT_nldm_211120 INVBUF_RVT_TT_nldm_220122 OA_RVT_TT_nldm_211120 \
         SEQ_RVT_TT_nldm_220123 SIMPLE_RVT_TT_nldm_211120; do
  curl -fsSL -O "$base/LIB/NLDM/asap7sc7p5t_$f.lib.7z"
  tar -xf "asap7sc7p5t_$f.lib.7z"           # bsdtar reads 7-Zip
  python3 -I ../trim_liberty.py "asap7sc7p5t_$f.lib" "asap7sc7p5t_$f.lib.gz"
done
curl -fsSL -o LICENSE "$base/LICENSE"
```

The AO and OA files are 22 MB and 20 MB of timing tables (about 4 MB each
compressed), so every file here is trimmed by `../trim_liberty.py`, which
removes each `timing`, `internal_power` and `leakage_power` group and copies
everything else byte for byte: cells, pins, directions, functions,
`three_state` and `clock`, `pg_pin` groups, `ff` and `latch` groups, areas
and comments. NetCrux's classifier reads nothing it removes. Trimmed, the
five files are 39 KB compressed. The oracle gives the same result for every
cell of the trimmed and the untrimmed files (checked when the files were
made).

## Expected symbols

Each `<file>.expected_symbols.json` is written by the independent oracle one
directory up, never by NetCrux:

```sh
python3 -I ../liberty_oracle.py --write asap7sc7p5t_*.lib.gz
python3 -I ../liberty_oracle.py --names asap7 asap7sc7p5t_*.lib.gz
```

Of the 202 cells, 109 are drawn as gates: 16 buffers, 21 inverters, 10 AND,
12 NAND, 10 OR, 11 NOR, 3 XOR, 3 XNOR, 17 flip-flops and 6 latches; the AO
and OA files are compound gates and all boxes. `../REVIEW.md` records the
cells whose names and functions disagree.

Written 2026-11-02 with Python 3.14.
