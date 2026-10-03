# Sources, projects & sessions

NetCrux distinguishes between the *sources* it elaborates and the *state* it saves about how you are looking at them. This page covers every input format, the project and filelist loaders, the auto-reload modes, and how sessions, workspaces and exports work.

| Artifact | Extension | What it holds |
|---|---|---|
| **Project** | `.netcrux-project` | A named source set for a design: sources, top module, include paths, defines. |
| **Suite manifest** | `<design>.crux-project` | The design, described once for every EDACrux product. |
| **Session** | `.netcrux` | One tab's view state — where you were and what you were looking at. |
| **Workspace** | `.netcrux-workspace` | A named set of tabs and panes. |

## Input formats {#inputs}

| Format | Extension | How it loads |
|---|---|---|
| Verilog / SystemVerilog | `.v`, `.vh` / `.sv`, `.svh` | Elaborated by Yosys `read_verilog` (IEEE 1364-2005 / IEEE 1800). |
| VHDL | `.vhd`, `.vhdl` | Lowered to Verilog by `ghdl --synth`, then read by Yosys (IEEE 1076). |
| NetCrux project | `.netcrux-project` | JSON describing sources, top module, include directories and defines. |
| Suite manifest | `<design>.crux-project` | YAML naming the design's sources or a pre-built netlist. See [below](#crux-project). |
| Vivado-style filelist | `.f` | Imported with `File → Import Vivado Filelist…` (++cmd+i++ / ++ctrl+i++). |
| Yosys JSON netlist | `.json` | Read directly — no Yosys run. See [below](#json). |

A netlist your own flow already wrote with Yosys `write_json` opens without elaboration: choose `File → Open Netlist JSON…` (also on the toolbar), pass it on the [command line](cli/usage.md) (`netcrux build/top.json`), or name it under `artifacts.netlist` in a [design manifest](#crux-project). It is also the only thing the [web viewer](web-mode.md) opens. NetCrux parses it and renders the top module exactly as if it had run Yosys itself, and the netlist file is watched for changes like any source. A single `.json` file is always read as a netlist, never handed to Yosys.
{: #json }

## Opening a design with `<design>.crux-project` {#crux-project}

A design usually spans more than one EDACrux product — the dump in WaveCrux, the RTL in NetCrux, the lint project in LintCrux, the regression suite in SimCrux. Without help that is four file-open rituals, each with its own recents list and its own chance of picking a stale file.

A design manifest at the root of your design replaces all four. It is a small YAML file named after the design, such as `uart_tx.crux-project`, that you write once and check in alongside the RTL:

```yaml
# uart_tx.crux-project
version: 1
name: uart_tx

design:
  top: uart_tx
  sources:
    - rtl/uart_tx.v

artifacts:
  waveform:   sim/uart_tx.vcd
  lint:       project.lintcrux
  simulation: simcrux.yaml
```

Open it with `File → Open Project…`, or pass it on the [command line](cli/usage.md) (`netcrux path/to/uart_tx.crux-project`), and NetCrux opens the part it owns. On the command line you can also pass the design directory itself (`netcrux path/to/uart_tx`) and NetCrux opens the manifest inside it. A design directory holds exactly one manifest: if it holds two, NetCrux names them and opens neither. That is either half of the manifest:

- **A pre-built netlist.** When `artifacts.netlist` names a Yosys JSON file, NetCrux renders it directly, without running Yosys. It wins over `design.sources`; if the file it names is missing, NetCrux says so rather than quietly elaborating the sources instead, which would hide a stale build.
- **The RTL.** Otherwise NetCrux elaborates every file under `design.sources`, in the order listed, with `design.top` as the top module.

Every path is relative to the manifest's own directory, so the file travels with the repository. The tab takes the manifest's `name`, and the manifest is what the recent-projects list remembers, so reopening it picks up any edits. All four products derive the same design identity from the manifest, which means cross-probing between them works exactly as it does when you open each file by hand.

A manifest from an earlier release is named just `.crux-project`, which file pickers hide; NetCrux still opens it and tells you the name to rename it to, and a later release stops reading the bare name.

**Everything except `version` is optional**, and keys a newer release understands but an older one does not are ignored, so a manifest never becomes unopenable. A manifest holds no view state and no personal settings — it says what the design *is*, not how you last looked at it. That is what sessions are for, and it is why a manifest is comfortable to share while a session generally is not.

## Opening sources directly {#open-sources}

1. **Choose the files.**

    Use `File → Open Source Files…` (++cmd+shift+o++ / ++ctrl+shift+o++) and select one or more HDL files. NetCrux detects the language from the extensions. The files open together in a new tab.

2. **Elaborate.**

    NetCrux runs Yosys (and GHDL for VHDL), reads the resulting netlist, and renders the top module. Close the tab with **Close Tab** (++cmd+w++ / ++ctrl+w++) or **Close Project** (++cmd+shift+w++ / ++ctrl+shift+w++).

## Projects {#projects}

A `.netcrux-project` file captures everything needed to re-elaborate a design: the source list, the chosen top module, include directories, `define` macros, and optionally extra Yosys commands and per-file language overrides. Relative paths resolve against the project file's own directory, so a committed project works from any checkout. Open one with `File → Open Project…` (++cmd+o++ / ++ctrl+o++), or pass it on the [command line](cli/usage.md). Use a project when a design needs more than a bare file list — defines, an explicit top, or a fixed include path. A project is the durable definition of a design; a session is a transient view of it.

## Importing a Vivado filelist {#filelist}

If you already maintain a `.f` filelist for a vendor flow, import it with `File → Import Vivado Filelist…` (++cmd+i++ / ++ctrl+i++). NetCrux reads the source paths, `+incdir+` directories and `+define+` macros out of the filelist — following nested `-f` includes, expanding `$VAR` / `${VAR}` environment variables, and reporting include cycles — and elaborates from there in a new tab. `-y`, `+libext+` and `--top` are not supported.

Source paths and `+incdir+` directories may contain spaces. A `+define+` value may not: Yosys has no way to accept one, so NetCrux reports the define as an error instead of elaborating without it. The same holds for the defines and include paths in a `.netcrux-project`.

Import it from inside NetCrux rather than double-clicking it. On Linux a `.f` file belongs to Fortran, and NetCrux deliberately leaves that association alone rather than taking `.f` from Fortran editors; a double-clicked `.f` therefore opens in whatever your desktop already uses for Fortran. Every other format on this page — projects, sessions, workspaces, design manifests and HDL sources — opens on a double-click.

## Auto-reload {#auto-reload}

NetCrux watches the source files behind the current schematic. What happens when they change on disk is set in `Settings → General → Auto-reload on source change`:

| Mode | Behavior |
|---|---|
| **Prompt me** *(default)* | Notify you that the source changed and offer to re-elaborate. |
| **Reload automatically** | Re-elaborate on save — the file-watching pattern of a modern editor. |
| **Don't reload** | Ignore changes; re-elaborate only when you reopen. |

## Sessions {#sessions}

A `.netcrux` **session** saves your view of a design. `File → Save Session As…` (++cmd+s++ / ++ctrl+s++) writes one once a design is laid out; it records the source files and top module, the current scope, the zoom and pan, the selection and trace-overlay mode, the expanded hierarchy-tree nodes, and any bookmarks and annotations. `File → Open Session…` (++cmd+l++ / ++ctrl+l++) loads one back into the active tab; `File → Open Project…`, `netcrux --session <file>` and `netcrux <file>.netcrux` open it in a tab of its own. The format is documented in [Session file format](reference/session-format.md).

Opening a session re-elaborates its sources and waits for the design before putting the view back: the scope you were in, the expanded hierarchy rows, the selection, and the zoom and pan. If a saved scope no longer exists in the design, the tab opens at the top, fitted to the view.

Sessions reference source *paths*; they do not embed your RTL, so a session is only meaningful on a machine that can see those files.

## Workspaces {#workspaces}

The workspace — every open tab and pane — is saved automatically and restored at launch while `Settings → General → Restore tabs on launch` is on. A tab opened from a `.netcrux-project` re-reads that file when it is restored, so its defines, include paths and extra Yosys commands apply, including any edits made since. Turning that off keeps the saved workspace on disk, so turning it back on brings your tabs back. To keep several sets of tabs, save a named `.netcrux-workspace` with `File → Save Workspace As…` and reopen it with `File → Open Workspace…` or `netcrux --workspace <file>`. `File → New Workspace` and `File → Reset Workspace…` close every tab after a confirmation. The welcome screen lists recent workspaces alongside recent projects and source files.

If the auto-saved workspace is corrupt at launch, NetCrux sets the file aside, tells you, and starts with a clean workspace rather than failing.

## Export {#export}

NetCrux exports the **current scope** in three formats. Each opens a save dialog and reports success or failure when the write completes; none of them exports the whole design.

| Format | Menu item | Key | Default file name | Contents |
|---|---|---|---|---|
| **PNG** | `File → Export as PNG…` | ++cmd+shift+e++ / ++ctrl+shift+e++ | `schematic.png` | A 2× raster of the visible canvas exactly as drawn, including the trace overlay and any dimming. |
| **SVG** | `File → Export as SVG…` | ++alt+e++ | `schematic.svg` | Vector geometry for the whole current scope — cells as labeled boxes, boundary ports and wires — on a dark background. No overlay or dimming. |
| **JSON** | `File → Export as JSON…` | ++alt+j++ | `schematic.json` | The netlist slice for the current scope: `{"creator": …, "modules": {"<name>": …}}`, pretty-printed. |

Use **PNG** for a bug report, chat message or slide (frame the view first — only what is inside the canvas is in the image), **SVG** for documentation where someone will zoom into the full scope, and **JSON** to hand the scope to another tool. If you need the whole netlist, run Yosys yourself with `write_json`.

!!! tip "Keymaps and themes travel as files too"

    Keyboard customizations export as a `.crux-keymap.json` file and color themes as `.crux-theme.json`. See [Keyboard & mouse reference](keyboard-mouse.md#customizing) and [Appearance & themes](appearance-and-themes.md#packs).
