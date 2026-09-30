# Inspector & RTL source

The schematic and the RTL are two views of the same design. NetCrux keeps them connected: the inspector tells you everything about a selected element, the RTL source pane shows the line that produced it, and the diagnostics panel surfaces whatever Yosys had to say while elaborating.

## The inspector {#inspector}

The right-hand **inspector** (toggle with ++cmd+2++ / ++ctrl+2++) shows the details of the current selection:

| Selection | What the inspector shows |
|---|---|
| Cell | **Instance**, **Type** (the Yosys cell type or module name), **Kind**, **Parameters** when the cell has any, and its **Ports** with their directions. |
| Port | The **Instance**, the port name, **Direction** and **Width**. A module boundary port shows `(boundary)` as its instance. |
| Wire | The **Net** name, **Net ID**, **Driver** and **Sinks**. |

Right-click an element on the canvas and choose **Open in Inspector** to make it the primary selection. Above the details, a **Go to source** button <span class="tier tier-pro">Pro</span> opens the element's RTL in the [RTL source pane](#source-pane). In Open Core it says it requires NetCrux Pro.

## The RTL source pane <span class="tier tier-pro">Pro</span> {#source-pane}

The **RTL source pane** brings the HDL into the app, kept in step with the schematic.

1. **Open the pane.**

    Run **Show RTL Source Pane** from the `View` menu or the command palette. The pane opens as a window over the workspace; **Close RTL Source Pane** dismisses it and keeps its place for next time.

2. **Jump from schematic to source.**

    Select a cell, port or net and choose **Show Source for this Element** — from the canvas context menu, the `Navigate` menu, the command palette, or the inspector's **Go to source** button. NetCrux uses the Yosys `src` attribute to resolve the element to its file and line and scrolls the read-only, syntax-highlighted Verilog / SystemVerilog / VHDL to it. An element Yosys recorded no location for shows "No source attribution recorded for this element."

3. **Navigate both directions.**

    The pane keeps a **bidirectional source ↔ schematic index**: identifiers in the source that map to schematic elements can be clicked to select those elements on the canvas.

!!! note "File size budget"

    The source pane loads files up to **8 MB** each. Larger files are not rendered inline — open them in your own editor.

## Opening source in your editor {#click-to-source}

`Settings → Editors → Editor command (open source)` is the command NetCrux runs when a [cross-probe](integrations.md) peer asks it to open a source location — for example `code -g {file}:{line}` for VS Code, which is the default. NetCrux substitutes `{file}`, `{line}` and `{column}` and runs the command; leave it empty to refuse such requests. The inspector's **Go to source** does not use it — that opens the in-app source pane.

## Elaboration diagnostics {#diagnostics}

The bottom **Diagnostics** panel (toggle with ++cmd+3++ / ++ctrl+3++, reveal with ++cmd+shift+i++ / ++ctrl+shift+i++) collects everything Yosys reported while elaborating: warnings and errors, each with a severity and, where Yosys gave one, a `file:line`. Filter with the severity chips (**Errors** / **Warnings** / **Info**) and use **Copy Report** on the panel's tab strip to put the whole list on your clipboard for a bug report or a colleague; each row also has its own copy button. Clicking a row copies its `file:line` to the clipboard so you can paste it into your editor. When elaboration fails outright — Yosys missing, a timeout, a non-zero exit — the panel shows an **Elaboration failed** banner with the reason, including GHDL's own message for a VHDL file it could not lower.
