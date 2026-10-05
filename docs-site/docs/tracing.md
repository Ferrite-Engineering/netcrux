# Tracing signals

"What drives this?" is the most valuable question a schematic browser can answer. NetCrux answers it at three levels of depth: one-step fanin and fanout in Open Core, and the transitive Cone of Influence and the X-Trace driver chain in Pro. All three work within the current scope.

## One-step fanin & fanout {#fanin-fanout}

Select a cell, port or net, then ask what touches it in one hop:

1. **Select a cell, port or net.**

    Click it on the canvas. The inspector confirms what you selected.

2. **Show fanin or fanout.**

    Press ++bracket-left++ (no modifier) for **Show Fanin** — the cells that directly drive the selection — or ++bracket-right++ for **Show Fanout** — its direct loads. The same commands are on the `Navigate` menu, the toolbar's **Trace** button, and the canvas context menu as **Trace Fanin** / **Trace Fanout**. The overlay includes the connected drivers (or loads), the edges that connect them, and the originating cell itself; everything else is dimmed, so the relevant subgraph reads at a glance.

3. **Frame the trace.**

    Press ++z++ (**Zoom to Selection**, also on the toolbar and the `Navigate` menu) to fit the view to the selection and everything the overlay highlights, so a trace whose drivers sit far apart is on screen at once. See [Zoom to Selection](navigating.md#zoom-to-selection).

4. **Clear the overlay.**

    Press ++escape++ (**Clear Selection / Overlay**) to remove the highlight and the selection. The overlay is anchored to the selection, so any click on the canvas also clears it.

Open Core tracing is deliberately one hop. Click a highlighted driver and press ++bracket-left++ again to walk back another level, and repeat until you reach a register, a module port or a constant. If the driver is a module port, pop out one scope (++cmd+bracket-left++ / ++ctrl+bracket-left++) and continue from the port on the parent side. If nothing highlights, the selection has no driver in this scope — check the boundary ports, and check the Diagnostics panel (++cmd+3++ / ++ctrl+3++) for Yosys warnings about the module.

## Cone of Influence <span class="tier tier-pro">Pro</span> {#cone}

Where the one-step overlay stops at the immediate neighbors, the **Cone of Influence** walks the whole transitive chain. From a selected cell or port it does a breadth-first traversal back through every driver (fanin cone) or forward through every load (fanout cone) until it runs out of connections — at the scope's boundary ports, or at cells with nothing further to follow. Registers do not stop the walk. It stays inside the current scope: it does not descend into submodule instances or climb into the parent.

1. **Run the cone from the selection.**

    Right-click a cell or port and choose **Show Cone of Influence (Fanin)** or **Show Cone of Influence (Fanout)** — the same commands are on the `Navigate` menu and the command palette. NetCrux paints the cone with an azure accent that stays visible at every zoom level, frames the view to the cone, and reports its size ("*N* cells in cone").

2. **Show only the cone.**

    With a cone active, right-click again and choose **Show Only Cone** — the schematic hides everything *outside* the cone, turning a dense module into just the logic that participates in your question. **Show Full Design** brings the rest back, dimmed.

3. **Clear it.**

    Choose **Clear Cone of Influence** (or press ++escape++) to drop the overlay and return to the plain schematic.

## X-Trace <span class="tier tier-pro">Pro</span> {#x-trace}

**X-Trace** walks the driver chain backward from a selected element, one step at a time, and reports *why* the walk stopped rather than just where. Results land in the **X-Trace** panel, which lists the chain step by step — each row naming the net and the cell or boundary port that drives it — and clicking a row selects that element and reveals it on the canvas. A name Yosys generated, which embeds the whole source path, shows as its cell type and `file:line` (`$add  dsp_mac.v:77`, or `$add  dsp_mac.v:77  (Y)` for the net it drives); hover the row for the full name. The whole chain is highlighted on the schematic at the same time.

Reach it by right-clicking a net, cell or port and choosing **Trace X Origin**, or from `Navigate → Show X-Trace` and the command palette. **Show X-Trace Panel** opens the panel on its own — useful empty, since it tells you what to select — and **Clear X-Trace** (or the panel's **Clear** button) empties the result while leaving the panel open. Closing the panel's tab keeps the chain, so reopening restores it.

X-Trace does not read simulation values yet: it follows the structural driver chain, so it answers "which path of drivers leads here", not "where did this X appear in my simulation".

### Which inputs the walk follows {#x-trace-inputs}

At each cell X-Trace follows **one** input, chosen by what the pin does:

- **Data inputs first.** A register's `D`, every input of a gate, an adder or a mux (the select included), and every input of a submodule instance count as data. The walk takes the first data input, in the cell's pin order, that leads somewhere it has not been.
- **Then control inputs.** A register's reset (`ARST`, `SRST`, async load, set and clear), then its enable, then its clock. These are followed only when no data route is left: when a register's data loops back on itself, as a counter's does, the reset is how an unknown would get in. This applies to Yosys's word-level and gate-level flip-flops and latches and to the iCE40 `SB_DFF` family.
- **Loops are stepped around.** When every input of a cell leads back onto the path, the walk backs up to the last cell that still has an untried input and continues from there. A register's hold loop (`q <= en ? d : q`) therefore leads on to `d`.

### What counts as an origin {#x-trace-origins}

The walk stops at the first cell that can produce an unknown by itself, and the panel says why:

| Reason shown | When |
|---|---|
| **undriven input** *pin* | An input of the cell is on a net nothing in the scope drives. The same pin draws the undriven stub on the canvas. |
| **input** *pin* **tied to x** | An input of the cell is tied to a constant with an `x` bit. A `case` with no `default` elaborates to one of these. |
| **register with no reset** | The cell is a flip-flop or latch with no reset on a net and no initial value, so it powers up unknown. A reset tied to a constant does not count; an initial value (`reg q = 1'b0;`) does, and iCE40 flops power up at 0. |
| **no driven inputs** | Nothing in the scope drives any input of the cell: a constant or other primary driver. |

An undriven or `x`-tied input wins over continuing up the cell's other inputs, because it is a certain source where a driven input is only a candidate. The last row of the chain names the origin cell.

### Why the walk stopped {#x-trace-status}

The status line at the top of the panel gives one of four reasons the walk stopped:

| Status | What it means |
|---|---|
| **Origin reached on this path** | The walk reached an origin, and the status adds the reason from the table above. |
| **Boundary reached** | The walk hit a boundary port of the current scope; the value comes from outside this module. |
| **Depth limit reached** | The chain was longer than the depth limit, and the walk stopped before an origin. |
| **Combinational cycle** | The driver chain loops back on itself with no other way out. |

A selection with nothing to trace from (a boundary *input*, which is itself a primary driver) offers no **Trace X Origin** entry, rather than running a walk that returns nothing. Selecting a cell starts the walk on the wire it drives, so the cell itself is checked first.

!!! note "A chain, not the chain"

    X-Trace reports *one* route back through a cone that usually has many. That is what makes it fast and readable, and it is worth knowing before you use a chain as evidence: it answers "where could this have come from", not "everywhere it could have come from". A fully reset design often has no origin in it at all, and the walk then ends at a boundary port. When you need the whole set, run [Cone of Influence](#cone) instead: it does not pick a path.

!!! note "Large designs trace in the background"

    On a big scope the cone and X-Trace walks run on a background isolate so the UI stays responsive — you keep panning and zooming while the trace computes, and the overlay appears when it is ready.

## Take the answer with you {#export}

[Export](files-and-projects.md#export) the view as PNG (++cmd+shift+e++ / ++ctrl+shift+e++) — it captures the canvas as drawn, overlay and dimming included. SVG export draws the plain schematic without the overlay.

!!! tip "Recipe"

    The [Trace a signal to its source](cookbook-trace-a-signal.md) recipe walks the whole fanin → cone → X-Trace progression on a real example.
