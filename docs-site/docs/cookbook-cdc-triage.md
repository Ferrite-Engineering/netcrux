# Triage a CDC crossing

A metastability bug is hiding at a clock-domain crossing somewhere in the design, and the linter gave you a hundred of them. This recipe uses NetCrux's on-schematic CDC view to find the crossings that actually lack a synchronizer and inspect the chain on the ones that have one.

| | |
|---|---|
| **Goal** | Find clock-domain crossings without proper synchronizers and confirm the structure of the ones that have them. |
| **Time** | About 8 minutes |
| **Tier** | <span class="tier tier-pro">Pro</span> — CDC analysis. |
| **You will use** | [CDC analysis](analysis.md#cdc), the [inspector](source-and-inspection.md#inspector), and [the RTL source pane](source-and-inspection.md#source-pane). |

## Before you start {#before}

Elaborate the design and make sure the clocks are real clocks — a CDC view is only as good as the design's clock structure. If a crossing looks wrong, the [reset-domain view](analysis.md#reset) is a useful companion. Know the analysis's blind spots: it does not recognize Gray-coded buses or verify handshakes yet, so those crossings come out rated critical and need a manual look.

## Steps {#steps}

1. **Run CDC analysis.**

    Choose `Tools → Run CDC Analysis Across Design…` or run it from the command palette. NetCrux lists every crossing in the docked **CDC Analysis** panel, grouped by source and destination domain, each classified by what it found (**2-flop sync**, **3-flop sync**, **Async FIFO**, **Metastable** or **Missing synchronizer**) with a severity of **Critical**, **Warnings** or **Info**.

2. **Filter to the critical crossings.**

    Use the severity chips to hide **Info** and focus on **Critical** — missing synchronizers and single-flop captures are the ones that can actually bite.

3. **Highlight one crossing.**

    Select a flagged crossing. NetCrux highlights its source and destination cells and any synchronizer flops on the schematic, so you can see the geometry of the crossing on the canvas.

4. **Inspect the synchronizer chain.**

    Follow the highlighted cells on the canvas and click the destination flops to read them in the [inspector](source-and-inspection.md#inspector). A proper synchronizer is two or three flip-flops in a row with nothing between them; a missing one feeds logic straight from the other clock domain.

5. **Jump to the RTL.**

    With the destination register selected, use **Go to source** (or **Show Source for this Element**) to open the [RTL source pane](source-and-inspection.md#source-pane) at the `always_ff` that should be doing the synchronizing, and fix it there.

!!! tip "Bookmark the bad ones"

    Right-click each unsynchronized crossing's destination and choose **Add Bookmark…**, with a note on what is wrong, so you have a punch list in the **Bookmarks** tab. Hover a row to read its note; click it to select that register again. Save the session to keep it.

## Where to go next {#next}

[Structural analysis](analysis.md) covers the CDC, reset-domain and FSM views together.
