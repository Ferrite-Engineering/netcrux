# Project file format (`.netcrux-project`)

A NetCrux project is a JSON document describing how to elaborate one design: its sources, top module, include directories, defines, cell libraries and Yosys options. `File → Save Project As…` writes one from the active tab, and `File → Open Project…` (++cmd+o++ / ++ctrl+o++) or `netcrux <file>.netcrux-project` opens it in a tab of its own. The format is small and stable, so a project can also be written by a script, such as a Tcl or shell wrapper that launches NetCrux from a compute farm. For what projects are for, see [Sources, projects & sessions](../files-and-projects.md#projects).

```json
{
  "version": 1,
  "sourceFiles": [
    "rtl/chip_top.v",
    "rtl/core/alu.sv",
    "/shared/ip/uart/uart_tx.v"
  ],
  "topModule": "chip_top",
  "defines": { "SYNTHESIS": "", "WIDTH": "32" },
  "includePaths": ["rtl/include"],
  "libertyFiles": ["/shared/pdk/stdcell/stdcell_tt.lib"],
  "blackBoxMissingModules": true
}
```

Only `version` is required. Every other field may be left out and takes the default in the table below, so the example above is a complete project.

## Fields

| Field | Default | Meaning |
| --- | --- | --- |
| `version` | (required) | Project schema version. Must be `1`. See [Compatibility](#compatibility). |
| `sourceFiles` | `[]` | HDL source paths, in the order Yosys reads them. The language comes from each file's extension unless `sourceFileLanguages` says otherwise. Leave vendor simulation models for standard cells out of this list and use `libertyFiles` instead. |
| `topModule` | `""` | The top module. Empty or absent lets Yosys choose the top of the hierarchy. |
| `defines` | `{}` | Preprocessor macros, as name to value. An empty value defines the name alone, like `+define+SYNTHESIS`. A value may not contain a space. |
| `includePaths` | `[]` | Directories searched for `` `include `` files, in order. |
| `libertyFiles` | `[]` | From NetCrux 1.1.3: Liberty (`.lib`, `.liberty`) cell libraries for RTL that instantiates standard cells or macros directly. NetCrux reads each cell's pins, buses and power pins and elaborates the cells as black boxes. When two libraries define a cell, the first in the list wins. From NetCrux 1.2, a library that is missing or cannot be read is skipped with a warning in Diagnostics instead of stopping the elaboration. See [Cell libraries](../files-and-projects.md#cell-libraries). |
| `blackBoxMissingModules` | `false` | From NetCrux 1.1.3: `true` draws a module that no source file or cell library defines as a black box instead of failing the elaboration, with pin directions inferred from the wiring. See [Missing modules as black boxes](../files-and-projects.md#black-boxes). |
| `extraYosysCommands` | `[]` | Yosys commands run after elaboration and before NetCrux reads the netlist, one command per entry, for example `"flatten"` or `"opt_clean -purge"`. Only in-memory passes are allowed. See [Extra Yosys commands](#extra-yosys-commands). |
| `sourceFileLanguages` | `{}` | Per-file language overrides, keyed by the path exactly as it appears in `sourceFiles`. Values are `verilog`, `systemverilog`, `vhdl` or `auto`. A file not listed is detected from its extension. |

`File → Save Project As…` writes every field in the table, leaving out `sourceFileLanguages`, `libertyFiles` and `blackBoxMissingModules` when they are empty or off. It also writes `lowerToStructural`, a field reserved for a future option that the current release reads and ignores. To draw processes and memories as gates and flip-flops today, set `extraYosysCommands` to `["proc", "opt", "memory", "opt"]`.

## Paths

- A relative path in `sourceFiles`, `includePaths`, `libertyFiles` or the keys of `sourceFileLanguages` resolves against the folder holding the project file, never the folder NetCrux was started from. A project committed next to its RTL therefore opens from any checkout.
- An absolute path is used as written, so a project can point at shared IP or a library outside its own tree.
- Environment variables such as `$PROJ_ROOT` are not expanded. A script that generates a project should write the paths out in full. A [Vivado-style filelist](../files-and-projects.md#filelist) does expand them, if you would rather keep them.
- `File → Save Project As…` writes paths relative to the project file when they share a root with it.

## Extra Yosys commands {#extra-yosys-commands}

A project file can arrive from anywhere: a download, a clone, an attachment. Its `extraYosysCommands` run as soon as the design elaborates, so NetCrux runs only commands that transform or inspect the design in memory. Those are the hierarchy and process passes (`hierarchy`, `proc`, `flatten`, `blackbox` and the like), the `opt` and `memory` families, the `fsm` passes, the coarse-cell and mux transforms, flip-flop legalization, renaming and attribute passes such as `rename` and `setattr`, and read-only inspection such as `stat`, `check` and `select`.

Commands that read or write files, run programs or load code are refused, including `exec`, `shell`, `tcl`, `script`, `plugin`, every `read_*` and `write_*` command, and `tee`. An entry may not contain `;`, a line break or a double quote. A project that breaks either rule does not open, and the message names the command it refused.

## Opening from the command line

```sh
netcrux /path/to/design.netcrux-project
```

On Linux, the Pro edition's command is `netcrux_pro`. Add `--yosys-path /path/to/yosys` to choose the Yosys executable for that run. See [Command-line usage](../cli/usage.md).

A tab opened from a project re-reads the file whenever the workspace is restored, so edits a script makes to the project file apply at the next launch.

## Compatibility {#compatibility}

Unknown fields are **ignored** on load, so a project written by a newer NetCrux still opens in an older one at the same version, without the fields the older build does not understand. Files written before NetCrux 1.1.3 have no `libertyFiles` or `blackBoxMissingModules` and open with neither.

A `version` other than `1`, a missing `version`, or a file that is not a JSON object is **rejected** with an error rather than partly loaded.

A project names its sources by path and does not embed them, so it is only meaningful on a machine that can see those files.
