# Structural analysis <span class="tier tier-pro">Pro</span>

Beyond browsing and tracing, Pro adds structural-analysis views that answer questions about the design as a whole — what changed between revisions, where clock domains cross, how reset propagates, and where state machines live.

!!! note "Analyses dock beside the schematic"

    Every analysis here — diff, CDC, reset-domain, FSM and the activity heatmap — opens as a tab in the dock beside the schematic rather than as a modal dialog. The drawing stays visible while you read the results, several analyses can be open at once, and you can drag a tab into the bottom dock. Selecting a row in a panel highlights the matching element on the canvas, and each panel header carries an **Open in WaveCrux** button that sends the selected element to a connected WaveCrux.

## Netlist Diff View <span class="tier tier-pro">Pro</span> {#diff}

The **Netlist Diff View** compares two elaborated revisions and tells you what a change did to the structure — not just what the source diff says.

1. **Load a comparison.**

    With the baseline revision open in the active tab, choose `File → Load Comparison Netlist…` (or **Load Comparison…** in the panel) and pick the other revision: all of its `.v` / `.sv` / `.vhd` files, or a Yosys JSON netlist it was already synthesized to. NetCrux elaborates the sources with the active tab's top module, defines, include paths and extra Yosys commands — so the diff shows what changed in the design, not in how it was elaborated — and compares the result against the active tab's design. A netlist is compared as-is. `View → Show Netlist Diff View` opens the panel on its own. If the comparison cannot be loaded — a missing file, no Yosys, an elaboration error — a message says why and the previous comparison stays on screen.

2. **Read the change chips.**

    Results are summarized as **Added** / **Removed** / **Modified** / **Unchanged** chips, with element-type chips for **Instances**, **Nets**, **Ports** and **Modules**, so you can focus on, say, only modified nets.

3. **Step through the changes.**

    Use the panel's previous and next arrows, or `Navigate → Previous Diff` / `Navigate → Next Diff`; the panel shows an "*N* of *M*" position so you know how far through you are. These commands have no default key binding; assign one in `Settings → Keyboard Shortcuts` if you want it.

4. **Scope the comparison.**

    Right-click an element on the canvas and choose **Compare with this Element in Baseline** to narrow the diff to that subtree, or use **Show in Schematic** on a change to jump the canvas to it. `File → Clear Comparison Netlist` (or **Clear** in the panel) drops the comparison.

!!! tip "Recipe"

    [Diff two RTL revisions](cookbook-diff-revisions.md) walks this end to end.

## CDC visualization <span class="tier tier-pro">Pro</span> {#cdc}

**CDC analysis** detects signals that cross between clock domains and lists the crossings in the docked **CDC Analysis** panel, grouped by source → destination domain. Run it with `Tools → Run CDC Analysis Across Design…`, or right-click a signal and choose **Show CDC Crossings for This Signal** to narrow the panel to that signal; `View → Show CDC Analysis Pane` opens the panel on its own.

Each crossing shows its kind (**Single-bit**, **Multi-bit**, **Control** or **Handshake**, inferred from the signal's width and name), its synchronizer classification, and a confidence. The classifications NetCrux produces are:

| Classification | What NetCrux found |
|---|---|
| **2-flop sync** | Two flip-flops cascaded in the destination domain. |
| **3-flop sync** | Three or more cascaded flip-flops. |
| **Async FIFO** | The destination cell or module name contains `FIFO` (a name match, medium confidence). |
| **Metastable** | One destination flip-flop, then logic that uses the value before it can settle. |
| **Missing synchronizer** | No flip-flop on the destination side — the signal feeds logic directly. |

Crossings are ranked by severity — **Critical**, **Warnings**, **Info** — with filter chips for each, so you can triage the risky ones first; **Re-run analysis** refreshes the result after a change. Selecting a crossing highlights its source, destination and synchronizer cells on the schematic; from there you can inspect the cells and jump to the RTL. See the [CDC triage recipe](cookbook-cdc-triage.md) for the full workflow.

!!! warning "Gray-code and handshake crossings are not classified"

    NetCrux does not yet recognize Gray-coded buses or verify request/acknowledge handshakes; both arrive in 1.1. A crossing labeled **Handshake** got that kind from its name alone (`_req`, `_ack`, `_valid`, `_ready`), and a Gray-coded pointer bus or a handshake-qualified data bus is reported as a multi-bit crossing and rated critical, the same as an unsynchronized bus. Review those by hand.

## Reset-domain visualization <span class="tier tier-pro">Pro</span> {#reset}

**Reset-domain analysis** (`Tools → Run Reset Domain Analysis Across Design…`) reports the design's reset domains in the docked **Reset Domain Analysis** panel, classifies each one's **polarity** (active-high or active-low), flags the places where data or a reset deassert **crosses a reset boundary**, and lists **Unreset registers** — flip-flops with no reset connection at all, which power up X — so a register that was never wired to a reset stands out instead of hiding in the netlist. Selecting a crossing highlights it on the canvas; **Show Reset Crossings for This Signal** on the context menu narrows the panel to one signal. Unreset registers are only reported when the design has at least one reset domain — a fully reset-less block is not flagged.

Both **asynchronous and synchronous** resets are recognized. Yosys lowers the two to different primitives — an async reset becomes an `$adff` carrying an `ARST` port, a synchronous one an `$sdff` carrying `SRST` — and each domain is classified accordingly, so a design that mixes them shows both, with the synchronicity reported per domain rather than assumed.

## FSM detection <span class="tier tier-pro">Pro</span> {#fsm}

**FSM detection** finds state registers and the next-state logic around them. `Tools → Run FSM Detection Across Design…` opens the docked **FSM Detection Results** panel, listing every detected FSM with its state count and encoding (**One-hot**, **Binary**, **Gray** or **Johnson**), plus candidate registers you can **Force detection** on. To check one register, right-click it and choose **Detect FSM for This Register**.

**Show diagram** (or `View → Show FSM Bubble Diagram`) renders the recovered machine as a docked **FSM Bubble Diagram** of states and transitions. The reset state carries a **RESET** badge; dead (trap) states — a state with no way out — are drawn with an error-colored bubble and a **DEAD** badge, with a callout naming them. Right-click the diagram to center on a state, highlight its outgoing transitions, or hide unreachable states.

!!! note "How states are named"

    States are labeled by their **RTL symbolic name** — for example `S_TRAP` — with the encoded value alongside. NetCrux recovers the names from `localparam` / `parameter` declarations in the Verilog or SystemVerilog source the state register came from; where that source is not readable, or a value has no plain-literal declaration, it falls back to a generated label such as `S3`.

## Switching-activity heatmap <span class="tier tier-pro">Pro</span> {#heatmap}

The **switching-activity heatmap** measures how often each net toggles in a simulation, colors the schematic's wires by it, and lists the result as **Hot Nets** and **Cold Nets** in the docked panel.

1. **Load a waveform.**

    Choose `File → Open Waveform File…` and pick a `.vcd` dump of a simulation of the design in the active tab. VCD is the only format the analysis reads. The waveform belongs to that tab; `File → Close Waveform File` unloads it.

2. **Run the analysis.**

    `Tools → Run Switching Activity Analysis` counts every net's transitions and duty cycle, colors each wire on the schematic by how hard its net toggles, and opens the panel with the hottest and coldest nets. Click a row to select that net on the schematic.

3. **Narrow the window.**

    The panel's **Full** / **First 10%** / **Middle 10%** / **Last 10%** chips choose the stretch of the simulation that is measured; changing them re-runs the analysis and recolors the wires.

4. **Pick a color scheme.**

    The panel's scheme menu, also reached through `Tools → Configure Activity Color Scheme…`, offers **Red-Blue heatmap** (blue for quiet nets through yellow to red for the busiest), **Viridis** and **Grayscale**. Both the wires and the panel's rows follow it.

5. **Clear the coloring.**

    `View → Clear Activity Coloring` returns the wires to their usual color and keeps the analysis in the panel. The wires stay uncolored until you run the analysis again or pick a scheme.

The coloring follows you through the design: push into an instance or pop back out and the new scope's wires are colored from the same analysis. Each tab colors its own schematic from its own waveform.

!!! note "Matching the waveform to the design"

    A simulator usually dumps the design under its testbench, so the design's top module `fsm_lock` appears in the VCD as a scope such as `tb_fsm_pass.dut`. NetCrux finds that scope by matching the design's net names and instance names against the waveform, so no prefix needs to be set. A wire stays its usual color when its net is not in the dump; that includes the internal wires synthesis creates, which have no counterpart in the simulation.
