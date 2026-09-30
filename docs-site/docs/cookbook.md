# Cookbook

The rest of these docs explain what each tool *is*. The Cookbook shows you how to put the tools together to get something done. Each recipe is a complete task — start with a design, end with an answer — written as numbered steps you can follow at the keyboard. They are short on purpose: a recipe is a worked example, not a manual.

!!! tip "No design handy?"

    Every recipe works against RTL you already have. If you just want to follow along, any small Verilog or VHDL design with a couple of registers and a clock will do — open it with `File → Open Source Files…` (++cmd+shift+o++ / ++ctrl+shift+o++), or open one of the projects under `examples/` in the `netcrux` repository.

## Recipes {#recipes}

- [Trace a signal to its source](cookbook-trace-a-signal.md) — Walk a signal from a load back to what drives it, escalating from one-step fanin to the Cone of Influence to X-Trace. **~8 min · Open Core + Pro**
- [Diff two RTL revisions](cookbook-diff-revisions.md) — Load a comparison netlist, filter to the modified elements, and jump straight to what changed. **~10 min · Pro**
- [Triage a CDC crossing](cookbook-cdc-triage.md) — Run CDC analysis, filter to the critical crossings, inspect a synchronizer chain, and jump to the RTL behind it. **~8 min · Pro**
- [Make a custom symbol](cookbook-custom-symbol.md) — Draw a symbol for a reusable module in the symbol editor and reuse it across projects. **~12 min · Pro**
- [Understand an unfamiliar module](cookbook/explore-unfamiliar-rtl.md) — Get the shape of a block you have never seen before you read a line of its RTL. **~10 min · Open Core**
- [Share a schematic in a review](cookbook/share-a-view.md) — Pick the right artifact — PNG, SVG, JSON or session — to show someone what you found. **~5 min · Open Core**
- [Cross-probe from a waveform](cookbook/cross-probe-from-waveform.md) — Go from a glitch in WaveCrux to the logic that produced it, and back. **~5 min · Open Core**

## How each recipe is laid out {#how-recipes-work}

Every recipe opens with a short summary — the goal, a rough time, the tier you need, and the features it exercises — followed by numbered steps. Keyboard shortcuts are written macOS first (++cmd++), with the ++ctrl++ equivalent for Linux and Windows. Where a step leans on a feature covered in depth elsewhere, it links straight to that page so you can go deeper without leaving the workflow.
