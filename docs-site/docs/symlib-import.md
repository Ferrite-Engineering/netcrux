# Symlib symbol libraries <span class="tier tier-pro">Pro</span>

From NetCrux 1.2, NetCrux Pro reads schematic symbols from symbol libraries in the **Symlib** text format, the ASCII symbol format of Nlview-based schematic tools, and draws every cell whose type a library names with that library's symbol. A design flow that already keeps a symbol per cell, and can write those symbols out as Symlib files, gets them in NetCrux with no drawing by hand and, through the project file or the command line, with no steps in the window at all.

Each symbol becomes an ordinary [custom cell symbol](customizing.md): it lays out in the drawing's shape with its pins where the library puts them, it is saved by **File → Save as SVG**, it shows in the Inspector's **Custom symbol** section and in the **Custom Cell Symbols** manager, and you can edit it there like any other.

## Load libraries {#load}

A library is a file, usually `.sym` or `.symlib`, holding any number of symbols. You can also name a folder: NetCrux then reads every `.sym` and `.symlib` file directly inside it (not in its subfolders), in name order. Libraries are read in the order they are given, and when two define a symbol of the same name, **the later one wins**; Diagnostics names each such conflict once.

There are three ways to load them, read in this order:

1. **The project file.** List the files or folders in the `symbolLibraries` key of the `.netcrux-project`. Relative paths are resolved against the folder holding the project file. They are read whenever the project's tab is the active one. See [Project file format](reference/project-format.md).

    ```json
    {
      "version": 1,
      "sourceFiles": ["netlist/top.v"],
      "libertyFiles": ["libs/cells.lib"],
      "symbolLibraries": ["symbols", "symbols/overrides.sym"]
    }
    ```

2. **The command line.** Give `--symbol-library <path>` once for each file or folder; a relative path is resolved against the folder NetCrux was started from. See [Command-line usage](cli/usage.md).

    ```bash
    netcrux --symbol-library /proj/symlib --symbol-library extra.sym design.netcrux-project
    ```

3. **The Symbol Manager.** Open `Tools → Open Custom Cell Symbol Manager…` and click **Import Symlib library…** to pick one or more files, or **Import Symlib folder…** to pick a folder. These are read for the current session only; to keep them, add them to the project's `symbolLibraries` key.

Libraries are read in the background, so a large set does not hold up the window, and each file is read once per version: NetCrux keeps what it read for a file until the file's size or modification time changes. As a measure of scale, 100 libraries of 300 symbols each (30,000 symbols) read in about one second on a recent desktop, and again in a few milliseconds once read.

The Symbol Manager says how many Symlib libraries are loaded. A symbol from a library carries a **Symlib** badge there, and the Inspector names its library under **Storage**.

## How a symbol is matched to a cell {#matching}

- **By name.** A symbol draws the cells whose type is exactly its name, case included: the Liberty cell name for a gate-level netlist, or the module name.
- **Pins by name.** Each port of the symbol is matched to the cell's pin of the same name. A port the cell does not have gets no pin; a pin of the cell with no port in the symbol is placed on its usual side (inputs left, outputs right). Both draw, and Diagnostics lists each mismatch once per cell type.
- **Your own symbols win.** A symbol made or edited in the Symbol Editor, in your user library or the project, takes precedence over one read from a Symlib library. To change a library symbol, edit it in the Symbol Manager and save: your copy is used from then on. A library symbol cannot be removed from NetCrux; take its library out of the list instead.
- **Organization packs.** An organization's symbol packs that are not locked rank below the Symlib libraries; locked packs rank above everything. See [Org-wide symbol libraries](administration.md#symbols).

## Where pins go and how big a symbol is {#geometry}

- **The box.** The symbol's `bboxnow` box is the frame of the drawing. A port connects where its `-locpath` (or `-loc`) starts, a point on the box's edge, and NetCrux puts the pin exactly there, on the side the port names. A port that names no side goes on the edge nearest to where it connects.
- **The size.** A symbol is drawn in its own units. NetCrux scales it so that the two closest pins on any one side are 10 layout units apart, the spacing of its own pins, so no pin has to move. A symbol with no two pins on the same side is drawn at half a layout unit per symbol unit. When a cell's pins need more room than that, the symbol is drawn larger, keeping its shape.
- **The drawing.** Lines are drawn in the canvas's line colour, in both light and dark themes. A text that repeats a port's name is left out, because NetCrux labels each pin itself; `@cell` shows the cell type, and `@name` is left to NetCrux, which draws every instance name outside its symbol.

## Supply pins {#supply}

A synthesized netlist leaves every cell's supply pins unconnected, and drawing them all would put four loose pins on every cell. NetCrux hides unconnected supply pins in a scope where no supply is wired, and draws all of them, connected or not, once any is. A cell drawn with a Symlib symbol follows the same rule:

- When the cell's Liberty description declares its power and ground pins (`pg_pin`), those are its supply pins.
- When there is no such description, the symbol's ports are judged by name: names starting `VDD`, `VCC`, `VPWR`, `AVDD` or `DVDD`, and `VPB`, `VNW`, `NWELL`, are power; names starting `VSS`, `GND`, `VGND`, `AVSS`, `DVSS`, `AGND` or `DGND`, and `VNB`, `VPW`, `PWELL`, are ground.

A supply pin's lead and label are left out of the drawing; NetCrux draws the pin, with its name, whenever the scope shows it.

## What NetCrux reads {#format}

The format has no public specification, so NetCrux reads the commands whose meaning is clear and skips the rest:

| Command | Read as |
|---|---|
| `symbol <name> [<view> [<type>]]` | Starts a symbol. A symbol is one command continued over lines ending in `\`; a line that starts with one of the commands below is also read as part of the symbol before it. |
| `port <name> <dir>[.<SIDE>] -locpath x y ...` | A port. `SIDE` is `LEFT`, `RIGHT`, `TOP` or `BOT`. The first point is where a wire connects; the rest are drawn as the pin's lead. |
| `port <name> <dir>[.<SIDE>] -loc x y [x2 y2]` | The same, connecting at `x y`, with a lead to `x2 y2` when given. |
| `path x y x y ...` | A line through the points, closed when the last point is the first. |
| `text <string> -<just>[.v] x y <size>` | A label. The justification's first letter is the vertical anchor (`u` upper, `c` centre, `l` lower), the second the horizontal one (`l`, `c`, `r`); `.v` turns the text to read upwards. A size with a unit letter after it (`6m`) is read without the letter. |
| `attrdsp @cell\|@name -<just>[.v] x y <size>` | Where the cell type and the instance name are shown. |
| `bboxnow x1 y1 x2 y2`, `bbox x1 y1 x2 y2` | The symbol's box. |
| `# ...`, blank lines | Ignored. |
| Lines before the first `symbol` | Ignored, as the library's header or index (`symlib`, `symref`). |

Coordinates grow rightwards and downwards. A symbol of type `DEF` is a custom drawing; a symbol of any other type is drawn from whatever drawing commands it has, and a cell whose symbol has none keeps NetCrux's own drawing.

## Limits {#limits}

- **Unknown commands are skipped.** A command NetCrux does not know (an arc, a circle, a filled shape, anything else) is left out of the drawing, and Diagnostics names it once per library, with how often it occurs and the line of the first. NetCrux never guesses what such a command's arguments mean; it takes them to end at the next word that could be a command. The same holds for a port option other than `-loc` and `-locpath`.
- **Broken commands are reported.** A `symbol` with no name, a `path` with fewer than two points, a box with fewer than four numbers, a `text` with no position, or a port with a malformed location is reported in Diagnostics with its line, and the rest of the library still loads. A symbol with no area, or with nothing NetCrux can draw, keeps NetCrux's own drawing.
- **Assumptions.** With no specification to check against, NetCrux assumes: the first point of `-locpath` is where a wire connects; a text's size is its height in symbol units; a text with no size is 8 units; `@name` is the instance name and `@cell` the cell type; a `.v` text reads upwards; an attribute display other than `@cell` and `@name` is not drawn; supply pins are recognised by the names above when the Liberty library is silent.
- **Bus pins** are matched by the cell's port name exactly as the netlist spells it.
- **Very thin or very wide symbols** are held between 1:5 and 5:1, like every custom symbol.
- **Session imports are not saved.** Libraries imported from the Symbol Manager are read again only if you add them to the project's `symbolLibraries` key or the command line.
- **Edits to the project file** take effect when the project's tab is opened or becomes the active tab.
