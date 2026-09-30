# Diff two RTL revisions

A PR claims to "just rename a signal," but the synthesis results moved. This recipe compares two revisions structurally — not line by line in the source, but cell by cell in the elaborated netlist — so you can see what the change actually did.

| | |
|---|---|
| **Goal** | See exactly which instances, nets, ports and modules a revision added, removed or modified. |
| **Time** | About 10 minutes |
| **Tier** | <span class="tier tier-pro">Pro</span> — the Netlist Diff View. |
| **You will use** | The [Netlist Diff View](analysis.md#diff), [split panes](interface.md#workspace), and the [RTL source pane](source-and-inspection.md#source-pane). |

## Before you start {#before}

Have both revisions on disk — two checkouts, or the same files at two commits. They can be any supported HDL; NetCrux elaborates each one before comparing, the new revision with the baseline's top module, defines and include paths. If your flow already produced a Yosys JSON netlist for the new revision, you can pick that instead.

## Steps {#steps}

1. **Open the baseline, and optionally the new revision beside it.**

    Open the baseline revision with `File → Open Source Files…` (++cmd+shift+o++ / ++ctrl+shift+o++). The diff compares against the design in the **active tab**, so keep that tab active. If you also want to look at the new revision, split the window with ++cmd+backslash++ / ++ctrl+backslash++ and open it in the second pane — each pane keeps its own scroll and zoom.

2. **Load the comparison.**

    With the baseline tab active, choose `File → Load Comparison Netlist…` and pick all of the new revision's source files (or its netlist `.json`). NetCrux elaborates them, compares the result against the baseline, opens the **Netlist Diff View** and summarizes the result as **Added** / **Removed** / **Modified** / **Unchanged** chips.

3. **Filter to what you care about.**

    Use the **Modified** chip to drop the unchanged noise, then the element-type chips (**Instances** / **Nets** / **Ports** / **Modules**) to focus — for a "just a rename" claim, look at modified nets and ports.

4. **Walk the changes.**

    Step through with the panel's arrows, or `Navigate → Next Diff` and `Navigate → Previous Diff`. The "*N* of *M*" counter tells you how many changes remain. These commands have no default key; bind one in `Settings → Keyboard Shortcuts` if you step through diffs often.

5. **Scope down and jump to source.**

    To investigate one subtree, right-click an element on the canvas and choose **Compare with this Element in Baseline** to limit the diff to it. Use **Show in Schematic** on a change to jump the canvas to it, then **Go to source** in the inspector to land on the RTL that produced it.

!!! note "Structural, not textual"

    The diff compares elaborated structure, so a pure source reformat that produces the same netlist shows as all **Unchanged** — which is exactly the signal you want when a PR claims to be a no-op refactor.

## Where to go next {#next}

[Structural analysis](analysis.md#diff) documents every chip and scope option in the Netlist Diff View.
