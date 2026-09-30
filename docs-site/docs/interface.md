# The interface

NetCrux is an IDE-style multi-pane application: a hierarchy tree on the left, the schematic canvas in the center, the inspector on the right, and diagnostics across the bottom. This page names every surface exactly as the app does, so the rest of the guide can refer to them precisely.

## Menu bar & toolbar {#menu-toolbar}

The menu bar carries the full command set under `File`, `View`, `Navigate`, `Search`, `Tools` and `Help`. On macOS it is the native menu bar, and the `NetCrux` application menu holds **About NetCrux**, **Check for Updates**, **Settings…** and **Quit NetCrux**; on Linux and Windows the menu bar is drawn inside the window, Settings and Exit sit at the bottom of `File`, and About and Check for Updates sit under `Help`. Menu entries for a Pro or Enterprise action carry their tier.

Below the menu bar, the **toolbar** surfaces the commands you reach for constantly: **Open Project…**, **Save Session As…** and **Close Project**; **Search…**, the **Cross-Probe Panel** toggle (with a badge counting connected peers) and **Settings…**; then **Open Source Files…**, **Open Netlist JSON…**, **Zoom In**, **Zoom Out**, **Zoom to Fit**, **Jump to Top**, **Pop Out of Scope**, and a **Trace** split button whose menu offers **Show Fanin**, **Show Fanout** and **Clear Selection / Overlay**. When the window is too narrow for the whole strip, it scrolls, and an **Actions** button appears at its end listing every menu command. Buttons grey out until they have something to act on — most need a laid-out design.

## The schematic canvas {#canvas}

The canvas is the center of the app and renders the elaborated netlist for the current scope:

- **Cells** are drawn as symbols. AND, OR, NOT, multiplexer, flip-flop and latch primitives get recognizable gate symbols; submodule instances and every other cell type are labeled rectangles.
- **Wires** route between ports; the enclosing module's own ports sit on the boundary.
- **Hierarchical instances** represent submodules — double-click one to push into it.
- A **three-band level-of-detail** system simplifies the drawing as you zoom out, so a large module stays legible. See [Navigating the schematic](navigating.md#lod).
- The **breadcrumb bar** above the canvas shows your scope path — for example `top › cpu › alu` — and each crumb is clickable to jump straight to that level.

**Pan** by dragging empty canvas, with the middle mouse button, with the scroll wheel or a two-finger trackpad scroll, or with the arrow keys; **zoom** with ++cmd++ / ++ctrl++ + scroll wheel or a pinch. Vertical and horizontal scrollbars flank the canvas, so off-screen cells are always reachable without a gesture. Selecting a cell, port or net highlights it and surfaces its details in the inspector. Right-click an element for its context menu: **Copy Path**, **Trace Fanin**, **Trace Fanout**, **Find in Hierarchy** and **Open in Inspector**, plus the Pro entries described elsewhere in this guide.

## Hierarchy tree {#hierarchy}

The left panel is the **hierarchy tree**: an expandable view of the module hierarchy. Each row shows the instance name and its module type — for example `cpu_core (cpu)` — and the number of cells in that scope. Type in **Filter scopes…** to narrow the tree by instance or module name, use the chevrons to expand and collapse, and click a row to show that scope on the canvas. Toggle the panel with ++cmd+1++ / ++ctrl+1++.

## Inspector {#inspector}

The right panel is the **inspector**, showing the details of whatever is selected:

- **Cell** — instance name, type, kind, parameters, and its ports with their directions.
- **Port** — the instance, port name, direction and width. A module boundary port shows `(boundary)` as its instance.
- **Wire** — net name, net ID, driver and sinks.

The **Go to source** button above the details, badged <span class="tier tier-pro">Pro</span>, opens the RTL behind the selection in the Pro [RTL source pane](source-and-inspection.md#source-pane); in Open Core it says it requires NetCrux Pro. Toggle the inspector with ++cmd+2++ / ++ctrl+2++.

## Diagnostics panel {#diagnostics}

The bottom **Diagnostics** panel lists the warnings and errors Yosys reported while elaborating. Severity filter chips (**Errors** / **Warnings** / **Info**) narrow the list, the **Copy Report** button on the panel's tab strip puts the whole list on your clipboard, and clicking a row copies its `file:line` so you can paste it into your editor's go-to-file dialog. Toggle the panel with ++cmd+3++ / ++ctrl+3++, or reveal it with `Tools → Tab Diagnostics…` (++cmd+shift+i++ / ++ctrl+shift+i++).

## Search & command palette {#finding-actions}

The **Search Design** dialog (++cmd+f++ / ++ctrl+f++) searches instance, cell and net names in every scope of the design, in **Substring**, **Glob** or **Regex** mode; choosing a result jumps to it on the canvas. The **command palette** (++cmd+shift+p++ / ++ctrl+shift+p++) is a fuzzy-filtered list of the actions available right now, each with its keyboard shortcut — every command on the menu bar is reachable from here without the mouse.

## Tabs & split panes {#workspace}

NetCrux is a **multi-tab workspace**: every design you open gets its own tab with its own scope, zoom, selection and overlay. ++cmd+w++ / ++ctrl+w++ closes the active tab (**Close Tab**) and ++cmd+shift+w++ / ++ctrl+shift+w++ is **Close Project**, which does the same. ++ctrl+tab++ and ++ctrl+shift+tab++ cycle tabs on every platform. Drag a tab to reorder it, or drop it on the other pane. **Split Pane Right** (++cmd+backslash++ / ++ctrl+backslash++) puts two canvases side by side, so you can compare two revisions at once. The workspace is saved automatically and its tabs come back at the next launch.

## Status bar, Settings & About {#status-settings}

The **status bar** along the bottom of each tab shows the first source file, the top module and the design's total cell count — the "what am I looking at" context — plus **Yosys not found** when the engine is missing and a busy indicator while elaboration runs.

**Settings** (++cmd+comma++ / ++ctrl+comma++) is organized into:

- **General** — **Auto-reload on source change** (**Prompt me** / **Reload automatically** / **Don't reload**), **Restore tabs on launch**, **Automatically check for updates**, and, in release builds, **Enable diagnostics surfaces**.
- **Appearance** — the **Language** picker (English, 中文, 日本語, 한국어), color presets, per-token color overrides and theme packs. See [Appearance & themes](appearance-and-themes.md).
- **Privacy** — **Send anonymous usage statistics**. See [Updates, issues & privacy](user-guide/updates-and-feedback.md#usage-statistics).
- **Engines** — the Yosys binary path.
- **Editors** — **Editor command (open source)**, the command NetCrux runs when a cross-probe peer asks it to open a source location.
- **CXP Cross-Probe** — the cross-probe server. See [Cross-probe & the suite](integrations.md#cxp-settings).
- **Keyboard Shortcuts** — view, edit, reset, import and export key bindings. See [Keyboard & mouse reference](keyboard-mouse.md#customizing).

The downloaded app adds **License** and **Collaboration** <span class="tier tier-enterprise">Enterprise</span>.

The **About box** (++f1++) shows the name and tagline, version, build and commit, platform details, the edition, Ferrite Engineering branding, and the elkjs (EPL-2.0) attribution, plus **Visit Website**, **Documentation**, **Submit Issue…**, **Check for Updates**, **Privacy Policy**, **Terms of Service**, **Acknowledgments** (the full open-source license list) and **Copy Version Info** actions.

!!! note "Next steps"

    Now that you can name every surface, learn [navigating the schematic](navigating.md) and [tracing signals](tracing.md).
