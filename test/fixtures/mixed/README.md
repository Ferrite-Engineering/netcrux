# Mixed Verilog + VHDL fixtures

A Verilog top module that instantiates a VHDL submodule. Exercises the
`crux_yosys` script generator's mixed-language path: Yosys emits the
`read_verilog` for `top.v` first, then loads the GHDL plugin and emits
`ghdl sub.vhd -e sub`. The submodule is wrapped in a Verilog black-box
declaration in `top.v` so the Verilog parser knows the module exists
before `hierarchy -check` rebinds it to the GHDL-produced one.

Used by:

- `test/integration/mixed_pipeline_test.dart` — real-yosys+ghdl
  end-to-end (skipped when GHDL / the plugin isn't on PATH).
- `test/services/project/mixed_language_script_test.dart` — pure-Dart
  assertion on the script generator's emit ordering.
