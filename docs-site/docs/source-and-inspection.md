# Inspector & RTL source

The schematic and the RTL are two views of the same design. NetCrux keeps them connected: the inspector tells you everything about a selected element, the RTL source pane shows the line that produced it, and the diagnostics panel surfaces whatever Yosys had to say while elaborating.

## The inspector {#inspector}

The right-hand **inspector** (toggle with ++cmd+2++ / ++ctrl+2++) shows the details of the current selection:

| Selection | What the inspector shows |
|---|---|
| Cell | **Instance**, **Type** (the Yosys cell type or module name), **Kind**, **Parameters** when the cell has any, and its **Ports**, each with its direction and what it is tied to. From NetCrux 1.2, a standard cell from the project's cell libraries also shows its **Cell library** data sheet (see below), and an instance of one of your modules shows its **Area**. |
| Port | The **Instance**, the port name, **Direction**, **Width** and **Tied to**. A module boundary port shows `(boundary)` as its instance and no tie. |
| Wire | The **Net** name, **Net ID**, **Driver** and **Sinks**. |

**Tied to** reads one of:

- the **net** the pin is on, by name (or `Net` and its ID when Yosys named none); a bus lists its nets most significant first, with the value of any bit tied to a constant;
- **Constant** and the value, when every bit is `0`, `1` or `z`;
- **x (unknown value)**, when every bit is `x`. Yosys ties unused inputs to `x` on purpose, for example the mask and write-data bits of an iCE40 block RAM, so an `x` pin is not by itself a fault;
- **Undriven (no driver in this scope)**, when any bit of the input is on a net that no cell output, inout or module input in this scope drives;
- **Unconnected**, when the cell's module or primitive declares the port but the netlist connects nothing to it.

The canvas marks the same ties with [pin stubs](interface.md#pin-stubs).

### A standard cell's data sheet (from 1.2) {#cell-data-sheet}

From NetCrux 1.2, selecting a cell whose type comes from one of the project's [Liberty cell libraries](files-and-projects.md#cell-libraries) adds three sections below the cell's details, read from the library:

| Section | What it shows |
|---|---|
| **Cell library** | **Function**: each output pin's Boolean function, as the library writes it, such as `Y = !(A&B)`. **Storage** for a sequential cell: `Flip-flop, next state D, clocked on CLK` or `Latch, data D, enabled by GATE`, with **Clear** and **Preset** when the cell has them. **Area**, in the library's units (square micrometres in common libraries). **Library file**: the Liberty file whose definition the design uses. **Defined in**: every library in the project that defines a cell of that name, each with the name its `library` group gives, which usually names its corner, such as `sky130_fd_sc_hd__tt_025C_1v80 (sky130_fd_sc_hd__tt_025C_1v80.lib)`. |
| **Library pins** | Each signal pin with its direction; a clock pin reads `input, clock`. |
| **Power and ground pins** | Each `pg_pin` with its `pg_type`, such as `primary_power`, `primary_ground`, `nwell` or `pwell`, or `no pg_type` when the library gives none. |

A cell whose type one of your sources defines as a module shows no data sheet, since that module is the definition the design uses. Selecting an instance of one of your own modules shows its **Area**: the area of every standard cell inside it, summed down its hierarchy, followed by `(partial)` when some cell inside has no area in any library. The [hierarchy tree](interface.md#hierarchy) shows the same sum on every scope's row.

**Parameters** show a number the way you would write it. Yosys stores a numeric parameter as a string of bits, so a `$dff` of width one carries `WIDTH` as `00000000000000000000000000000001`; the inspector shows `1`. A value that needs more than eight bits also shows its hex form, such as `4294901760 (0xFFFF0000)`, and a value wider than 64 bits shows hex alone. Hover the row to see the bits exactly as Yosys wrote them. A parameter that is a real string, or has `x` or `z` bits, is shown as written.

Right-click an element on the canvas and choose **Open in Inspector** to make it the primary selection. From NetCrux 1.2 the entry is called **Properties** and also puts the keyboard focus in the inspector, as `View → Properties` and ++alt+enter++ do. Above the details, a **Go to source** button <span class="tier tier-pro">Pro</span> opens the element's RTL in the [RTL source pane](#source-pane). In Open Core it says it requires NetCrux Pro.

## The RTL source pane <span class="tier tier-pro">Pro</span> {#source-pane}

The **RTL source pane** brings the HDL into the app, kept in step with the schematic. It opens as a **Source** tab in the dock beside the schematic, next to the Inspector and any open [analyses](analysis.md), so the drawing stays visible and interactive while you read the code.

1. **Open the pane.**

    Run **Show RTL Source Pane** from the `View` menu or the command palette. The Source tab opens in the right dock, or comes to the front if it is already open. Close it with the tab's **×** or **Close RTL Source Pane**; the pane keeps its file and line for next time. Like the analysis tabs, it can be dragged into the bottom dock.

2. **Jump from schematic to source.**

    Select a cell, port or net and choose **Show Source for this Element** from the canvas context menu, the `Navigate` menu or the command palette, or use the inspector's **Go to source** button. NetCrux uses the Yosys `src` attribute to resolve the element to its file and line, opens the Source tab, and scrolls the read-only, syntax-highlighted Verilog / SystemVerilog / VHDL to that line and highlights it. An element Yosys recorded no location for shows "No source attribution recorded for this element."

3. **Navigate both directions.**

    The pane keeps a **bidirectional source ↔ schematic index**: identifiers in the source that map to schematic elements are underlined, and clicking one selects that element on the canvas beside the pane. **Jump to element** in the pane's status bar selects the element under the last identifier you clicked again.

The code lays out at its own width: in a narrow dock, long lines scroll sideways inside the pane rather than being cut off, and the file path above the code shortens to fit. Widen the dock by dragging its edge.

!!! note "File size budget"

    The source pane loads files up to **8 MB** each. Larger files are not rendered inline: open them in your own editor.

## Opening source in your editor {#click-to-source}

`Settings → Editors → Editor command (open source)` is the command NetCrux runs when a [cross-probe](integrations.md) peer asks it to open a source location, for example `code -g {file}:{line}` for VS Code, which is the default. NetCrux substitutes `{file}`, `{line}` and `{column}` and runs the command; leave it empty to refuse such requests. The inspector's **Go to source** does not use it: that opens the in-app source pane.

## Elaboration diagnostics {#diagnostics}

The bottom **Diagnostics** panel (toggle with ++cmd+3++ / ++ctrl+3++, reveal with ++cmd+shift+i++ / ++ctrl+shift+i++) collects everything Yosys reported while elaborating: warnings and errors, each with a severity and, where Yosys gave one, a `file:line`. Filter with the severity chips (**Errors** / **Warnings** / **Info**) and use **Copy Report** on the panel's tab strip to put the whole list on your clipboard for a bug report or a colleague; each row also has its own copy button. Clicking a row copies its `file:line` to the clipboard so you can paste it into your editor. When elaboration fails outright (Yosys missing, a timeout (see [The Yosys time limit](getting-started.md#yosys-time-limit)), a non-zero exit) the panel shows an **Elaboration failed** banner with the reason, including GHDL's own message for a VHDL file it could not lower.
