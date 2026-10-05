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

    A cell or net you named in the source is listed by its name. One Yosys generated (its name starts with `$`) is listed by its cell type and the file and line it came from, such as `$add  gray_counter.v:14`. A generated net reads the same way, followed by the pin it comes from: `$add  gray_counter.v:15  (Y)`. Hover the row for its full name. A folder with spaces in its name shows as written, even though Yosys spells each space `$20` inside the full name.

3. **Step through the changes.**

    Use the panel's previous and next arrows, or `Navigate → Previous Diff` / `Navigate → Next Diff`; the panel shows an "*N* of *M*" position so you know how far through you are. The arrows walk the list top to bottom as it is shown, and each step selects that change on the schematic the way **Show in Schematic** does. These commands have no default key binding; assign one in `Settings → Keyboard Shortcuts` if you want it.

4. **Scope the comparison.**

    Right-click an element on the canvas and choose **Compare with this Element in Baseline** to narrow the diff to that subtree, or use **Show in Schematic** on a change to jump the canvas to it. `File → Clear Comparison Netlist` (or **Clear** in the panel) drops the comparison.

### Show in Schematic {#diff-show}

The schematic shows the baseline: the design in the active tab. Click a row to show its element: the row becomes the active one (the "*N* of *M*" position follows it) and that row's element, never a neighbour, is selected on the schematic. Clicking the active row again shows it again. The row's **Show in Schematic** button does the same. It is the target icon at the row's right end and stays in view however narrow the panel is: the element's name is cut short first. Hover the icon for its name; in a wide panel the button also carries the words **Show in Schematic**.

Showing an element:

- a **cell** is selected, its scope becomes the shown scope, and the canvas centers on it;
- a **net** has every drawn strand selected, and the canvas centers on the cell driving it;
- a **port** is selected on the boundary of its module's scope;
- a **module** becomes the shown scope.

**Removed**, **Modified** and **Unchanged** elements are all in the baseline, so all of them can be shown. An **Added** element exists only in the comparison netlist: there is nothing on the schematic to show, so its button is disabled, and its tooltip says so. Clicking an Added row makes it the active row and clears the schematic selection, so nothing stays selected that belongs to another row.

### How elements are matched {#diff-matching}

Modules, ports, and the cells and nets you named in the source are matched by name. A name that exists on one side only is reported as added or removed.

The cells and nets Yosys generates (`$add`, `$xor`, `$procdff`, their output wires) are named after the source file, the line and a running counter, as in `$add$/home/me/rtl/gray_counter.v:14$3`. Those names change whenever an edit moves a line, and differ outright between two files, so they are not used to match. Instead each generated cell is matched by its type, its parameters, and what its pins connect to: the named nets and ports it touches, and, step by step, the generated cells between it and them. Generated nets are matched by the cells on their bits. Only what is left without a match is reported as added or removed. As a result:

- inserting a comment line at the top of a file changes every generated name, and the diff reports no change;
- comparing `gray_counter.v` with a copy whose Gray-code conversion became `bin + 1` reports one `$add` and one `$xor` removed, with their three output nets, and nothing else.

A matched element is **Modified** when its type, parameters, port widths or (for a net or port) width differ. A module is **Modified** when its ports, cell count or net count change. The source location never counts: an edit above an element moves its line without changing it.

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

Crossings are ranked by severity — **Critical**, **Warnings**, **Info** — with filter chips for each, so you can triage the risky ones first; **Re-run analysis** refreshes the result after a change. Selecting a crossing paints the crossing itself on the schematic in its severity colour (red for critical, amber for a warning, green for info): the wires of the crossing net, every bit of a bus; the source-domain register that drives it; the destination-domain register that captures it; and the synchronizer flops or the logic in between. A crossing with no synchronizer paints too, so an unsynchronized bus shows its source register, its capture register and all of its wires. The highlight covers the cells in the scope you are viewing; from there you can inspect the cells and jump to the RTL. See the [CDC triage recipe](cookbook-cdc-triage.md) for the full workflow.

**Clear a crossing** to remove its paint from the schematic in any of these ways: press ++escape++, which also clears the selection and any fanin or fanout trace; click the selected row again; choose **Clear** in the panel header; close the CDC Analysis panel; or use `View → Clear CDC Analysis Selection`. Clearing keeps the analysis result, so the panel still lists every crossing.

**Show CDC Crossings for This Signal** works on the right-clicked wire, pin, port or cell. When the tab already has a result for the loaded design, NetCrux uses it; it runs the analysis only when there is none yet, or when the design has changed since (a re-elaboration or a reload). Once a result exists, the entry appears only on elements that take part in a crossing: the crossing net's wires, the pins and ports on it, the registers that drive or capture it, and its synchronizer flops. If the signal takes part in several crossings, the panel lists only those, with a chip above the list naming the signal; choose the chip's **×** to see every crossing again. The panel always scrolls to the selected crossing and flashes it, even when it was already selected. From the command palette, the command uses the current schematic selection.

!!! warning "Gray-code and handshake crossings are not classified"

    NetCrux does not yet recognize Gray-coded buses or verify request/acknowledge handshakes; both arrive in 1.1. A crossing labeled **Handshake** got that kind from its name alone (`_req`, `_ack`, `_valid`, `_ready`), and a Gray-coded pointer bus or a handshake-qualified data bus is reported as a multi-bit crossing and rated critical, the same as an unsynchronized bus. Review those by hand.

## Reset-domain visualization <span class="tier tier-pro">Pro</span> {#reset}

**Reset-domain analysis** (`Tools → Run Reset Domain Analysis Across Design…`) reports the design's reset domains in the docked **Reset Domain Analysis** panel, classifies each one's **polarity** (active-high or active-low), flags the places where data or a reset deassert **crosses a reset boundary**, and lists **Unreset registers** — flip-flops with no reset connection at all, which power up X — so a register that was never wired to a reset stands out instead of hiding in the netlist. Selecting a crossing paints it on the canvas in its severity colour, the same way a CDC crossing paints: the crossing net's wires, the register that drives it, the destination register and its reset synchronizer flops; **Show Reset Crossings for This Signal** on the context menu narrows the panel to one signal. Unreset registers are only reported when the design has at least one reset domain — a fully reset-less block is not flagged.

A reset crossing clears the same ways a CDC crossing does: ++escape++, clicking the selected row again, **Clear** in the panel header, closing the Reset Domain Analysis panel, or `View → Clear Reset Analysis Selection`. **Show Reset Crossings for This Signal** follows the CDC rules too: it reuses a current result, appears only on elements that take part in a reset crossing once a result exists, filters the panel to that signal's crossings behind a chip when there are several, and always scrolls to the selected crossing and flashes it.

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
