# case_decoder: captured fixture provenance

A wide `case` statement, the shape of an instruction decoder or an ALU's
operation select, written for NetCrux and elaborated by Yosys. Committed for
what its shape does to the layout: Yosys makes one comparator per case item,
63 `$eq` cells and one `$logic_not` (for item 0), and every one of them feeds
the select input of a single `$pmux`. Their inputs, the bits of `op`, reach
all 64 of them, so those nets are too wide to route, and the layered layout
put all 64 comparators in one layer: a column about eleven times as tall as
the drawing was wide (531 x 5898 layout units). The selector bank
(`lib/services/layout/selector_bank.dart`) lays them out as a grid instead;
`test/services/layout/selector_bank_test.dart` holds it to that, and the
layout parity gate keeps a stored ELK reference (elkjs output) of the scope
(`test/fixtures/layout/case_decoder.case_decoder.elkjs.json.gz`).

## `case_decoder.v` (source)

- **Written for:** NetCrux, for this fixture.
- **License:** Apache-2.0, like the rest of this repository (SPDX:
  `Apache-2.0`).
- **sha256:** `6763415bb59b9832ecb736d8ea86aa8e4ccd65d13678682d0f7202adb630054b`
- **Module:** `case_decoder` (8-bit `op`, 32-bit `a` and `b`, 32-bit `y`).

## `case_decoder.netlist.json` (elaborated netlist)

- **Produced by:** Yosys 0.70+post (git sha1 `0c11ea098be`), NetCrux's own
  elaboration (`proc` after `hierarchy`), run beside the source:

  ```sh
  yosys -q -p "read_verilog case_decoder.v; hierarchy -check -top case_decoder; \
    proc; write_json case_decoder.netlist.json"
  ```

  The `creator` field in the document records the Yosys build. The run read
  the source by its absolute path; the directory was then removed from every
  `src` attribute, so each reads `case_decoder.v:<line>`, and nothing else in
  the document was changed.
- **sha256:** `7cb29ff11529a1fd8502833d961451a5c9817af3694941235590c0c6af08f11b`
- **Shape:** 1 module, 73 cells (63 `$eq`, 1 `$logic_not`, 1 `$pmux` and
  one each of `$add`, `$sub`, `$and`, `$or`, `$xor`, `$shl`, `$shr`, `$lt`),
  4 ports, 87 nets.
- **Opening it in NetCrux:** File → Open Netlist JSON…, or open
  `case_decoder.v` itself with Yosys on the PATH.
