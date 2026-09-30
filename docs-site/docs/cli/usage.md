# Command-line usage

```text
netcrux [--workspace <file>] [--session <file>] [--yosys-path <path>]
        [--no-restore] [--reset] [--reset-telemetry-consent] [--reset-eula]
        [-h | --help]
        [<project.netcrux-project> | <session.netcrux> | <design.crux-project>
         | <design directory> | <netlist.json> | <source files...>]
```

NetCrux is a desktop application with a command-line front door. Every invocation opens a window, except `--help`.

## Options

| Flag | Effect |
| --- | --- |
| `--workspace <path>` | Open a saved `.netcrux-workspace`. You are asked to confirm before it replaces the current workspace. |
| `--session <path>` | Open a `.netcrux` session file in a new tab: its design is re-elaborated and its view state restored. |
| `--yosys-path <path>` | Use this Yosys binary for this launch, overriding `Settings → Engines`. |
| `--no-restore` | Launch without restoring the previous tabs. Nothing is deleted; the next normal launch brings them back. Try this first if the app hangs on startup. |
| `--reset` | Delete the saved workspace and per-tab session state, then launch empty. Settings, keymap and recent files are kept. |
| `--reset-telemetry-consent` | Testing aid: forget this installation's usage-statistics answer so the first-launch choice appears again. Has a visible effect only on builds where usage statistics are live. |
| `--reset-eula` | Testing aid: forget this installation's acceptance of the licence agreement so it is presented again on this launch. |
| `-h`, `--help` | Print usage to stdout and exit with status 0; the app does not start. |

`--workspace`, `--session` and `--yosys-path` accept both `--flag value` and `--flag=value`; they are the only flags that take a value. An unrecognized flag is ignored rather than rejected, and the argument after it is still read.

## Positional arguments

| Input | Effect |
| --- | --- |
| Exactly one `*.netcrux-project` | Opened as a project. |
| Exactly one `*.netcrux` | Opened as a session, like `--session`. |
| Exactly one `*.crux-project` | Opened as a suite design manifest: its netlist, or its sources and top module. See [design manifests](../files-and-projects.md#crux-project). |
| Exactly one directory | The one `*.crux-project` manifest inside it is opened. A directory with no manifest, or with more than one, is refused with a message naming what it found. |
| One or more other paths | Opened as source files, one tab each. A `*.json` file is read as a pre-built Yosys netlist, without elaboration. |
| No arguments | The saved workspace is restored (unless `Settings → General → Restore tabs on launch` is off). |

Precedence: `--workspace` wins over `--session`, which wins over positional arguments.

## Examples

```bash
# Open two source files in two tabs
netcrux rtl/top.v rtl/alu.v

# Open a project with a specific Yosys
netcrux --yosys-path /opt/oss-cad-suite/bin/yosys soc.netcrux-project

# Open a netlist your synthesis flow already wrote
netcrux build/top.json

# Open a design from its manifest, or from the directory holding it
netcrux designs/uart_tx/uart_tx.crux-project
netcrux designs/uart_tx

# Restore a review workspace
netcrux --workspace review.netcrux-workspace
```

## Caveats

There is no `--version`, `--top` or `--ghdl-path` flag.

Unknown flags are not rejected — they are stripped, and the argument after one is read as a path. A misspelled value flag therefore turns its value into a file to open: `netcrux --yosys-pth /opt/yosys/bin/yosys top.v` tries to open the Yosys binary as a source. Check your spelling.

## Web builds

The web viewer ignores the command line entirely. See [Web viewer](../web-mode.md).
