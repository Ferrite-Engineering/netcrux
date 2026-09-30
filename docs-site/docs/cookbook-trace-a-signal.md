# Trace a signal to its source

You are looking at a net with a value you do not trust, and you want to know what put it there. This recipe walks from "what drives this?" back toward the origin, escalating through the three tracing tools as the question gets harder.

| | |
|---|---|
| **Goal** | Find the logic, register or boundary port that drives a suspect net. |
| **Time** | About 8 minutes |
| **Tier** | Open Core for one-step fanin; the Cone of Influence and X-Trace are <span class="tier tier-pro">Pro</span>. |
| **You will use** | [Fanin / fanout](tracing.md#fanin-fanout), [Search Design](navigating.md#search), the [Cone of Influence](tracing.md#cone), [X-Trace](tracing.md#x-trace), and the [inspector](source-and-inspection.md#inspector). |

## Before you start {#before}

Elaborate the design ([Installation & first elaboration](getting-started.md)) and find the suspect net. If you are not sure where it is, open **Search Design** (++cmd+f++ / ++ctrl+f++) and type its name — switch to **Glob** or **Regex** if the exact name is fuzzy. Choosing a **Net** result navigates to its scope and selects the cell that drives it, which is already the first answer. (An undriven net leaves nothing selected: it is a module input or a constant.)

## Steps {#steps}

1. **Select the net and take one hop back.**

    Click the net, then press ++bracket-left++ for **Show Fanin**. NetCrux highlights the cells that directly drive it and dims everything else. Often that is enough — if a single cell drives it, you have your answer.

2. **Walk back, or widen to the cone.**

    In Open Core, click a highlighted driver and press ++bracket-left++ again, one level at a time, until you reach a register (the value comes from the previous cycle — now you want its data input), a constant, or a module port. With Pro, right-click the driving cell or port and choose **Show Cone of Influence (Fanin)** to pull in the whole transitive driver chain at once. NetCrux frames the view to the cone and reports its size; choose **Show Only Cone** to hide everything else. Clear it any time with ++escape++.

3. **Run X-Trace for one concrete chain.** <span class="tier tier-pro">Pro</span>

    Right-click the net and choose **Trace X Origin** (or use `Navigate → Show X-Trace`). It walks the driver chain backward, opens the **X-Trace** panel with one row per step, and reports why it stopped: **Origin reached** (a driver with no inputs, such as a constant), **Boundary reached** (the value comes in from outside this module), **Combinational cycle**, or **Depth limit reached**. Remember that X-Trace follows one input pin per cell — the cone shows every route.

4. **Confirm at the source.**

    Click a row in the X-Trace panel to select and reveal that element on the schematic, then read the [inspector](source-and-inspection.md#inspector) — for a register you will see its type and ports. With Pro, **Go to source** opens the RTL source pane at the line that defines it.

!!! tip "When the trace crosses a module boundary"

    A driver that is a module port, or a **Boundary reached** result, means the signal comes from the parent scope. Pop out with ++cmd+bracket-left++ / ++ctrl+bracket-left++, select the matching port on the instance you came from, and continue from there.

## Gotchas {#gotchas}

- ++bracket-left++ and ++bracket-right++ are **bare keys**. ++cmd+bracket-left++ / ++ctrl+bracket-left++ pops out of a scope, which is a different action.
- Nothing highlights on ++bracket-left++? The selection has no driver *in this scope* — check the boundary ports, and check the Diagnostics panel (++cmd+3++ / ++ctrl+3++) for Yosys warnings about the module.
- Press ++bracket-right++ instead of ++bracket-left++ to see loads — "what breaks if I change this?". The same walk applies.
- ++escape++ clears the overlay and the selection when the dimming gets in your way.

## Where to go next {#next}

[Tracing signals](tracing.md) covers fanin, the cone and X-Trace in full, including all four X-Trace stop reasons.
