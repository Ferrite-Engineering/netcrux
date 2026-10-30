# Sources, projects & sessions

NetCrux distinguishes between the *sources* it elaborates and the *state* it saves about how you are looking at them. This page covers every input format, the project and filelist loaders, the auto-reload modes, and how sessions, workspaces and exports work.

| Artifact | Extension | What it holds |
|---|---|---|
| **Project** | `.netcrux-project` | A named source set for a design: sources, top module, include paths, defines, cell libraries. |
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
| Liberty cell library | `.lib`, `.liberty`, `.lib.gz`, `.liberty.gz` | Read for its cells' interfaces, which Yosys sees as black boxes. A gzip-compressed library is read as it is. See [Cell libraries](#cell-libraries). |
| Yosys JSON netlist | `.json` | Read directly — no Yosys run. See [below](#json). |

A netlist your own flow already wrote with Yosys `write_json` opens without elaboration: choose `File → Open Netlist JSON…` (also on the toolbar), pass it on the [command line](cli/usage.md) (`netcrux build/top.json`), or name it under `artifacts.netlist` in a [design manifest](#crux-project). It is also the only thing the [web viewer](web-mode.md) opens. NetCrux parses it and renders the top module exactly as if it had run Yosys itself, and the netlist file is watched for changes like any source. A single `.json` file is always read as a netlist, never handed to Yosys. The file is read from disk in chunks rather than loaded whole, so its size is not limited: a netlist of several gigabytes opens, and the memory it takes is that of the design once parsed, about 4 to 5 GB for every million cells. (The [web viewer](web-mode.md) receives the document as text, so very large netlists belong in the desktop app.)
{: #json }

From NetCrux 1.2, a netlist read this way gets the same pin direction inference as the [black boxes](#black-boxes) option. A flow that reads a cell library with `read_liberty -lib` and runs `hierarchy` without `-check` leaves the library's power and ground pins out of each cell's module but keeps the instances' connections to them, and Yosys writes every such connection as an output, so a supply net looks driven by every cell on it. NetCrux takes the direction of each connection to a pin its cell's module does not declare from the wiring, keeps the directions of the pins the module does declare, and lists the pins as `CELL.PIN` in the Diagnostics panel. A cell whose type no module in the netlist defines is handled the same way, with all its pins inferred. Directions are inferred, so a pin the wiring does not decide is shown as an input.

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

Any `.lib` or `.liberty` file selected with the sources becomes one of the tab's [cell libraries](#cell-libraries) rather than a source.

## Cell libraries {#cell-libraries}

RTL that instantiates standard cells directly, such as an analog top level or hand-placed buffers, needs a definition for every cell, because NetCrux elaborates with `hierarchy -check`. The vendor's simulation models are the wrong place to get one: they are written for simulators and use constructs Yosys cannot read, such as UDPs and `specify` blocks. Leave them out of the source list and add the library's Liberty file instead.

From NetCrux 1.1.3, a project carries a list of Liberty (`.lib`) files. NetCrux reads each cell's pins with their directions, its buses with their widths, and its power and ground pins (`pg_pin`), which become `inout` ports so an instance that connects `VDD` and `VSS` elaborates. Each cell reaches Yosys as a black box. If your sources define a module with a cell's name, that definition is used instead. When two libraries define the same cell, the first in the list is used and the Diagnostics panel says so.

Add cell libraries in any of these ways:

- `File → Cell Libraries (Liberty)…` lists the active tab's libraries, with **Add…** and a remove button for each. **Apply** re-elaborates the design.
- `File → Open Source Files…` accepts `.lib` and `.liberty` files alongside the sources.
- A `.f` filelist entry ending in `.lib` or `.liberty` is a cell library.
- A `.netcrux-project` lists them under `libertyFiles`.

From NetCrux 1.2, each of these also takes a gzip-compressed library, named `.lib.gz` or `.liberty.gz`, so a library does not have to be unpacked first. NetCrux decompresses it as it reads, a block at a time, and never holds the decompressed text, so it needs no more memory than the plain file would. The file pickers show every `.gz` file (the platform file dialogs match only the last part of a name), but only a name ending in `.lib.gz` or `.liberty.gz` is treated as a cell library. A `.gz` file that is not valid gzip data is skipped with a warning in Diagnostics like any unreadable library.

A list changed with `File → Cell Libraries (Liberty)…` stays with the tab across restarts, even when the tab's project file does not list it; `File → Save Project As…` writes it into the project.

Liberty files run to hundreds of megabytes, almost all of it timing tables. NetCrux reads only the cell interfaces and keeps the result in its app-support folder, keyed by each file's path, size and modification time (for a compressed library, those of the `.gz` file), so a library is read once until it changes. A library that is missing or is not valid Liberty is skipped, and the Diagnostics panel shows a warning with the file name, the line for a syntax error, and the reason. Before NetCrux 1.2 such a library stopped the elaboration instead. The design still elaborates with the other libraries, and the cells of the skipped one count as missing modules: with [black boxes](#black-boxes) on they are drawn as black boxes, and otherwise the elaboration stops with "is not part of the design" for the first cell it cannot find. Fix or remove the file in `File → Cell Libraries (Liberty)…` and apply.

### Missing modules as black boxes {#black-boxes}

Without a library at hand, a design that instantiates a module nothing defines stops with "is not part of the design". From NetCrux 1.1.3 the error view offers **Show missing modules as black boxes**, which turns the option on for the tab's project and elaborates again. The same option is a checkbox in `File → Cell Libraries (Liberty)…`, and a `.netcrux-project` stores it as `"blackBoxMissingModules": true`.

With the option on, each instance of a missing module is drawn as a box with the pins its instance connects. A positional connection has no pin name to show, so its pins are `$1`, `$2` and so on, in the instance's order. Nothing says which way a pin points, so NetCrux infers it from the wiring:

- A pin on a net that something else drives (a module input, a constant, another cell's output) is an input.
- A pin that is the only possible driver of a net that other cells or a module output read is an output.
- A pin the wiring does not decide is shown as an input.

A power pin tied to a supply or a constant therefore shows as an input. The Diagnostics panel lists the module types drawn this way and how many pins were guessed. Directions are inferred, so use this for viewing; a [cell library](#cell-libraries) gives the exact pins. The vendor's simulation models still have to be left out of the source list, since Yosys cannot read them either way.

From NetCrux 1.2 the option also covers a pin that an instance connects but its cell's definition does not declare, such as a bulk or well-tie pin that one variant of a cell library leaves out. Before, Yosys drew that pin as an output, so a ground net looked driven by every such cell. Now the pin's direction is inferred from the wiring in the same way, the pins the definition does declare keep their declared directions, and the Diagnostics panel lists the pins as `CELL.PIN`. With the option off, an instance that connects a pin its cell lacks still stops the elaboration.

From NetCrux 1.2, black boxes apply to the built-in reader only. When a design uses SystemVerilog that the built-in reader refuses and NetCrux reads it with yosys-slang instead (see [which SystemVerilog it reads](getting-started.md#systemverilog-subset)), yosys-slang cannot leave a module undefined. It stops at the first module nothing defines, the error view names that module, and the black-box option is not offered, because turning it on would fail the same way. A design read by yosys-slang needs a definition for every module it instantiates: add the source file that defines the module, or a [cell library](#cell-libraries), whose cells reach yosys-slang as black boxes with their exact pins.

## Projects {#projects}

A `.netcrux-project` file captures everything needed to re-elaborate a design: the source list, the chosen top module, include directories, `define` macros, and optionally extra Yosys commands, per-file language overrides and [cell libraries](#cell-libraries). Relative paths resolve against the project file's own directory, so a committed project works from any checkout. Open one with `File → Open Project…` (++cmd+o++ / ++ctrl+o++), or pass it on the [command line](cli/usage.md). Use a project when a design needs more than a bare file list: defines, an explicit top, or a fixed include path. Every field is listed in the [project file format](reference/project-format.md), which a script can also write. A project is the durable definition of a design; a session is a transient view of it.

`File → Save Project As…` (from NetCrux 1.1) writes the active tab's project as a `.netcrux-project`: the source list, top module, include directories, defines, cell libraries and Yosys options the tab elaborates with, whether they came from a project file, a filelist import or files opened one by one. Source, include and cell-library paths are written relative to the project file's directory when they share a root with it, so the file can be committed and opened from another checkout; a path on another drive stays absolute. The tab then treats the new file as its project file, so a restore re-reads it, and the file joins **Recent Projects**.

## Importing a Vivado filelist {#filelist}

If you already maintain a `.f` filelist for a vendor flow, import it with `File → Import Vivado Filelist…` (++cmd+i++ / ++ctrl+i++). NetCrux reads the source paths, `+incdir+` directories, `+define+` macros and [cell libraries](#cell-libraries) out of the filelist, following nested `-f` includes, expanding `$VAR` / `${VAR}` environment variables and reporting include cycles, and elaborates from there in a new tab. `-y`, `+libext+` and `--top` are not supported.

An imported filelist is listed under **Recent Projects** on the welcome screen and reopens from there, and `netcrux <design>.f` opens one from a shell. A tab opened from a filelist re-reads it when the workspace is restored, the same way a `.netcrux-project` tab does, so its defines and include directories apply at the next launch too.

Source paths and `+incdir+` directories may contain spaces. A `+define+` value may not: Yosys has no way to accept one, so NetCrux reports the define as an error instead of elaborating without it. The same holds for the defines and include paths in a `.netcrux-project`.

Import it from inside NetCrux rather than double-clicking it. On Linux a `.f` file belongs to Fortran, and NetCrux deliberately leaves that association alone rather than taking `.f` from Fortran editors; a double-clicked `.f` therefore opens in whatever your desktop already uses for Fortran. Every other format on this page — projects, sessions, workspaces, design manifests and HDL sources — opens on a double-click.

## Auto-reload {#auto-reload}

NetCrux watches the source files behind the current schematic. What happens when they change on disk is set in `Settings → General → Auto-reload on source change`:

| Mode | Behavior |
|---|---|
| **Prompt me** *(default)* | Notify you that the source changed and offer to re-elaborate. From 1.1 this is a banner across the top with **Ignore** and **Reload**, which stays until you choose. |
| **Reload automatically** | Re-elaborate on save — the file-watching pattern of a modern editor. |
| **Don't reload** | Ignore changes; re-elaborate only when you reopen. |

From NetCrux 1.2 the three segments read **Prompt**, **Auto** and **Off**, in that order, and mean what the rows above say: **Prompt** is **Prompt me**, **Auto** is **Reload automatically** and **Off** is **Don't reload**.

## Sessions {#sessions}

A `.netcrux` **session** saves your view of a design. `File → Save Session As…` (++cmd+s++ / ++ctrl+s++) writes one once a design is laid out; it records the source files and top module, the current scope, the zoom and pan, the selection and trace-overlay mode, the expanded hierarchy-tree nodes, and any annotations. `File → Open Session…` (++cmd+l++ / ++ctrl+l++) loads one back into the active tab; `File → Open Project…`, `netcrux --session <file>` and `netcrux <file>.netcrux` open it in a tab of its own. The format is documented in [Session file format](reference/session-format.md).

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
