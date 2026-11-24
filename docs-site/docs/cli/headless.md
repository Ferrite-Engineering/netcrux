# The headless command line

From NetCrux 2.0, a second executable, `netcrux`, answers questions about a design without opening a window: what the top module is, which cells and nets have a given name, what a cell is wired to or what drives a net. It has no graphical interface and needs no display, so it runs in a terminal, a script, a CI job or an SSH session. The desktop application's own options are on [Command-line usage](usage.md); this page is the headless executable.

```text
netcrux info <design>... [--top <module>] [--json]
netcrux search <design>... <query> [--top <module>] [--kind <kind>] [--glob] [--limit <n>] [--json]
netcrux connections <design>... <name> [--top <module>] [--json]
netcrux mcp [--root <dir>] [--license-file <path>]
netcrux --version
netcrux --help
```

`netcrux <command> --help` prints the flags of one command. The three commands are free in every edition, and none of them reads a licence.

## What a design can be

Every command takes a design as one or more positional arguments, before any query or name. A design is one of:

- **Sources.** Verilog, SystemVerilog or VHDL files, and `.f` filelists of them, in any mix. NetCrux elaborates them with the Yosys found on `PATH`, the way the desktop app does. A filelist's `+define+` and `+incdir+` lines are passed on.- **One Yosys JSON netlist,** as written by `yosys write_json`. It is read as it is, with no elaboration, so Yosys need not be installed.
- **One `.crux-project` manifest,** which names either sources or a netlist. See [design manifests](../files-and-projects.md#crux-project).

A netlist or a manifest is the whole design: give it alone. Mixing one with other files is refused.

The command line does not read everything the app does. These are refused with a message that says what to give instead:

| Given | Outcome | What to do |
| --- | --- | --- |
| A `.netcrux-project`, a `.netcrux` session or a `.netcrux-workspace` | Usage error | Give its sources, a Yosys JSON netlist, a `.crux-project` or a `.f` filelist. |
| A Liberty cell library (`.lib`, `.liberty`), alone or named by a filelist or a manifest | Input error | Give the design as a Yosys JSON netlist, or open it in the app. |
| A directory | Input error | Give the manifest file inside it. |

`--yosys-path` and `--netlist-reader` belong to the desktop app and are not flags of the headless commands: the headless executable runs the Yosys on `PATH`, plus the engine directories the app adds. The native gate-level reader is the app's, so a gate-level Verilog netlist is elaborated by Yosys here.

`--top <module>` chooses the top module. Without it, the top is the manifest's declared top, or the one Yosys picks or the netlist marks. A netlist that marks a different top from the `--top` you gave is an input error rather than being re-rooted.

## The commands

### info

`netcrux info <design>...` elaborates the design and reports the top module, the number of modules, the cells and named nets of every module (each module counted once), and the instances in pre-order with each one's module and cell count. The instance list stops at 200 instances and says so with `truncated`.

### search

`netcrux search <design>... <query>` finds cells, nets, ports and modules whose name contains the query, ignoring case. Each hit carries its path, module, type (a cell's type, a port's direction), width and location. The query is always the last argument.

| Flag | Effect |
| --- | --- |
| `--kind <kind>` | Only this kind of element: `cell`, `net`, `port` or `module`. Any other value is a usage error. |
| `--glob` | Match the whole name with `*` and `?` instead of a substring. |
| `--limit <n>` | Hits to return, a whole number from 1 to 500. The default is 50. A larger number is a usage error, not clamped. |

The answer carries `total`, `returned` and `truncated`. Narrow the query or raise `--limit` to see more. A search counts at most 100,000 cells and nets, and a warning says so when `total` is only a floor.

### connections

`netcrux connections <design>... <name>` takes the hierarchical, dot-separated name of a cell or a net, rooted at the top module (`top.u_core.alu_y`), as `search` returns it. A name written from just below the top (`u_core.alu_y`) is read the same way. For a cell it lists each pin with its direction and the net on it. For a net it lists the pins that drive it and the pins it drives. It is one step, inside the module that holds the cell or net, and stops at 500 pins. A name that is both a cell and a net resolves to the cell, with a warning. A name that is neither is an input error.

## Reading the answer

Without `--json`, a command writes a short summary to standard output and any warnings and errors to standard error, each error with a `fix` line when there is one.

With `--json`, a command writes one JSON document to standard output and nothing else. It always has the same eight members: `schema_version`, `tool`, `command`, `outcome`, `engines`, `design`, `body` and `diagnostics`. `design.fingerprint` is the same value for the same design files, top and defines, so two runs can be compared. `body` is the answer, or `null` when there is none.

**The `outcome` is the authority.** Read `body` only when `outcome` is `completed`. On any other outcome, read the `error` diagnostics: the message says what went wrong (for a Yosys failure, Yosys's own error line). The exit code follows the outcome:

| Outcome | Exit code | Typical cause |
| --- | --- | --- |
| `completed` | 0 | An answer. Check the warnings. |
| `usage_error` | 64 | A missing or bad argument, an unknown command or flag, a project, session or workspace file, a flag value out of range. Running `netcrux` with no arguments also exits 64. |
| `input_error` | 65 | No such file, a Liberty library, a netlist that is not one, no such top module, no cell or net by that name, an unusable manifest. |
| `engine_error` | 3 | Yosys is missing, stopped with an error (including an error in the HDL), or timed out. |

`--help` and `--version` exit 0.

Every cell, net and port carries a `location` with its file, its element and, where the netlist records one, the `src` line it came from. A `netcrux://` link is there when NetCrux can open that element; `link` is `null` when it cannot, for example when the design was given as a filelist or a manifest of sources, or the schematic does not draw the element. See [Cross-probe & the suite](../integrations.md) for links.

## Examples

```bash
# The top module and hierarchy of a design
netcrux info rtl/top.sv rtl/alu.sv

# The same, from a filelist, as JSON
netcrux info rtl/files.f --json

# Every cell with "fifo" in its name, from a netlist your flow already wrote
netcrux search build/top.json fifo --kind cell --json

# Cells whose whole name matches a pattern, at most 20
netcrux search design.crux-project 'fifo*' --kind cell --glob --limit 20

# What drives a net, and what it drives
netcrux connections design.crux-project top.u_core.alu_y --json
```

In a script, test the exit code, then read `body`:

```bash
netcrux info build/top.json --json > info.json
case $? in
  0)  echo "answer in info.json" ;;
  64) echo "bad command line" ;;
  65) echo "bad input" ;;
  3)  echo "Yosys failed" ;;
esac
```

## netcrux mcp

`netcrux mcp --root <dir>` serves the same three commands as tools over the Model Context Protocol, on standard input and output (newline-delimited JSON-RPC), for an MCP client such as an editor or an assistant that you configure to start it. Each tool takes the same inputs as its command's flags and returns, as its first text content, the same document the command writes with `--json`, byte for byte.

| Flag | Effect |
| --- | --- |
| `--root <dir>` | Every path a tool receives must be inside this directory, and so must every file a `.crux-project` or `.f` filelist names. The default is the working directory. A path outside it, a symbolic link that leads outside it or a network path is refused and never opened. |
| `--license-file <path>` | Accepted for compatibility with the editions that serve licensed tools. The three tools here read no licence. |

The server writes nothing into the directory and makes no network call of its own. It keeps the two designs it read last, so several calls about one design elaborate it once, and elaborates a design again when a source changes. A root that does not exist is a usage error and exits 64. The server exits 0 when its input closes.

The server counts tool calls as usage statistics only under the consent recorded by the desktop app on the same machine, and never when the `CI` environment variable is set. See [Updates, issues & privacy](../user-guide/updates-and-feedback.md).

For what to configure in a client, how an assistant should cite what it finds and how to read a document, see the NetCrux agent page in the EDACrux documentation.
