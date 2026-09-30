# Understand an unfamiliar module

Someone handed you a block you have never seen, and you want its shape before you read a line of Verilog. This recipe gets you from a pile of source files to a mental block diagram using nothing but Open Core.

| | |
|---|---|
| **Goal** | Learn a module's interface, data path and hierarchy from the schematic. |
| **Time** | About 10 minutes |
| **Tier** | Open Core. |
| **You will use** | [Navigation](../navigating.md), the [inspector](../source-and-inspection.md#inspector), [one-step tracing](../tracing.md#fanin-fanout) and [Search Design](../navigating.md#search). |

## Steps {#steps}

1. **Open the sources.**

    `File → Open Source Files…`, or `File → Import Vivado Filelist…` if the project already has a `.f`. If Yosys can pick the top on its own it will; otherwise open a `.netcrux-project` that names it.

2. **Start at the top.**

    Press ++cmd+home++ / ++ctrl+home++, then ++cmd+0++ / ++ctrl+0++ to fit. This is the block diagram: submodule instances as symbols, the module's own ports on the boundary.

3. **Read the interface.**

    Click each boundary port and check the inspector (++cmd+2++ / ++ctrl+2++) for its direction and width. Press ++bracket-right++ on an input port to see what it feeds inside.

4. **Follow the data path.**

    Select the main input port and press ++bracket-right++, then click a highlighted load and press it again, one hop at a time. You are walking the pipeline in the order the data flows.

5. **Descend where it matters.**

    Double-click a submodule to push into it; ++cmd+bracket-left++ / ++ctrl+bracket-left++ comes back up. The breadcrumb keeps you oriented, and the hierarchy tree (++cmd+1++ / ++ctrl+1++) shows the overall shape with a cell count per scope.

6. **Check the size.**

    The status bar shows the cell count for the whole elaborated design — a fast sanity check for "is this a small glue block or a big one?".

7. **Remember where you were.**

    With `Settings → General → Restore tabs on launch` on, the tab comes back at the next launch. **Copy Path** on the canvas context menu puts an element's full path on the clipboard for your notes.

    For a view you want to come back to deliberately rather than automatically, `File → Save Session As…` (++cmd+s++ / ++ctrl+s++) writes a `.netcrux` session. Reopening one re-elaborates its sources and then puts the view back — the scope you were in, the expanded hierarchy rows, the selection, and the zoom and pan. If the saved scope no longer exists in the design, the tab opens at the top, fitted. The trace overlay is deliberately not restored: re-issue the trace and it recomputes. See [Sessions](../files-and-projects.md#sessions).

## Tips {#tips}

- Search (++cmd+f++ / ++ctrl+f++) in **Glob** mode is the fast way to find the clock and reset nets: `*clk*`, `*rst*`.
- Elaboration results are cached, so reopening the same sources is instant.
- Set `Settings → General → Auto-reload on source change` to **Reload automatically** while you are editing the RTL — save the file and the schematic re-elaborates.
