# Slack overlay <span class="tier tier-pro">Pro</span>

From NetCrux 1.2, **View → Show Slack Overlay** colours the registers of the open
design by the worst slack an implementation run states, and lists the same data
in a table. It reads the run's own timing report and states what the report
states. The overlay invents nothing: a figure the run does not give is shown as
not stated, never filled in. Results are findings from one run, not a statement
that a design is ready for anything.

The command is in the menu in every build, badged **Pro**. In an open core build
it says that it requires NetCrux Pro. With a Pro, EDU or Enterprise license it
opens the **Slack** dock tab. The [timing path SimCrux sends you](integrations.md#receive-timing)
is free in every edition; only the overlay is Pro.

## What it reads {#reads}

A run is a nextpnr result folder, or its `report.json`. iCE40, ECP5, Gowin and
GateMate all write the same schema. A folder with no `report.json` is not a
nextpnr run and is refused with a message that does not repeat its path. LibreLane
runs are not read by this overlay.

There are two ways to open one:

- **From SimCrux.** With SimCrux running and the same design open, send a run
  from SimCrux's Flow Runs. NetCrux opens it in the active tab and docks the Slack
  tab, and SimCrux is told it was honoured. A relative path, a directory sent as a
  report or a file sent as a run is refused, with a reason that does not repeat the
  path.
- **From the tab.** **Open run folder…** and **Open timing report…** open a picker.

Opening a run is announced with its size and worst slack. A report over the size
cap, or nested too deeply, is refused when it is opened.

## What the colours mean {#colours}

Each flip-flop of the open design that a path of the run ends or starts at is
outlined and softly filled on the schematic, from the cold end of a colour ramp
(the most slack) to the hot end (the least). The ramp is one of the three
activity colour schemes, chosen in the panel, and the same call draws the
schematic, the legend and the table's swatch.

- A cell is drawn only when its register is in the scope on screen. Push into a
  sub-block and only that block's registers are drawn. A module instantiated
  twice puts each register in its own instance.
- With only one slack stated, a violated slack is shown hot and a met one cold,
  and the legend says it is the only slack stated.
- A register the run mentions that your design does not have gets a row from the
  tool's own cell name, unmapped, with no swatch and nothing drawn.

## How slack is stated {#slack}

A path's slack is the one the run states. For a path launched and captured by the
same edge of one clock, with no slack stated, it is that clock's constraint
period less the path delay. A path between two clocks, on opposite edges, or from
or to an unclocked port states none: the register still has a row, reading "none
stated", uncoloured, and the panel counts these paths instead of guessing.

The **Net delay** column is the largest delay the run lists for the register's
output net. It needs the report's detailed net timings, is read after the table
appears, and is empty for a register the run does not list.

## Fidelity {#fidelity}

Every end of every path goes through the same mapping SimCrux uses, against the
elaboration your tab holds. An end that cannot be placed stays unmapped. An end
named only by the statement that assigns a register is labelled **statement**,
never **nearest register**, and the label of each row says how its register was
found. See [Fidelity labels](integrations.md#fidelity).

## The panel {#panel}

The **Slack** tab holds **Open run folder…**, **Open timing report…** and **Close
run**; the run's name and verdict (a token that is never translated); its clocks;
a one-line size; the colour switch and scheme pick; the legend with both ends of
the scale in nanoseconds; and the table.

The table is the text alternative to the colours, so colour is never the only
channel. It is one Tab stop; the arrow keys, ++home++ and ++end++ move between
rows; ++enter++ or a click puts the register on the schematic and frames its
cell; the headers sort, and a second click on the sorted header flips the order.
Each row has one spoken sentence, for example "src_a, slack -15.419 ns, launch and
capture, mapping nearest register".

Turning the colour switch off returns the schematic to its ordinary look; the
legend and the table stay.
