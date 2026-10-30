# Use in VS Code

The **NetCrux extension** draws a Yosys netlist as a schematic inside VS Code, and lets you ask "what drives this signal?" from the editor, with the cursor already on the identifier, and answers it in a running NetCrux schematic.

It installs from the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.netcrux) and from [Open VSX](https://open-vsx.org/extension/ferrite-engineering/netcrux), which is where Cursor, Windsurf, VSCodium and Theia install from. To install all four EDACrux extensions at once, install the [EDACrux Suite](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.edacrux) pack.

## Schematic preview { #preview }

The preview opens a Yosys JSON netlist, the file `write_json` produces, as a schematic next to your RTL. It is the same viewer as the [web viewer](web-mode.md), running inside VS Code, so nothing is uploaded and it works offline.

To open one:

- Right-click a `.json` file in the Explorer, or its editor tab, and choose **Open Schematic Preview**.
- Or choose **Open With...** on the file and pick **NetCrux Schematic Preview**.
- With a netlist open as text, the preview button appears in the editor title bar.

The extension reads the start of the file to check that it is a Yosys netlist before it opens the preview, and says so if it is not. It never takes over ordinary JSON: **Open With...** is the only way a `.json` file opens in the preview without that check, and double-clicking a file still opens it as text.

In the preview you can:

- Move through the hierarchy, push into an instance and pop back out.
- Search by instance, cell or net name, and trace one step of fan-in and fan-out.
- Select an element to see its properties, and open **Cone View** to see only what drives it.
- Choose **Go to Source in Editor**, from the right-click menu on the schematic or the Inspector, to open the RTL behind an element at its line in VS Code. The netlist records the source file and line of each element in its `src` attribute. A relative path is looked for next to the netlist and in the open folders, and a path from another machine is matched by its file name. Only files inside the folders you have opened are shown.

The preview follows your VS Code theme, and when a synthesis run rewrites the netlist the schematic reloads.

### Large netlists { #large }

The preview reads the whole netlist into the editor's memory, so it stops at a size limit, **32 MB** by default. Above it the preview does not load the file; it offers **Open in NetCrux** instead, because the desktop app reads a netlist from disk and has no size limit. The limit is the `netcrux.preview.maxFileSizeMB` setting, which you can raise up to 256 MB.

### Open in NetCrux { #open-in-netcrux }

**Open in NetCrux** hands the netlist to the desktop app. It is in the editor title bar of the preview, on the right-click menu, and in the Command Palette. It also opens the Pro features, which the preview does not have.

- If NetCrux is running, the netlist opens in it.
- If NetCrux is installed but not running, the extension starts it with the netlist.
- If NetCrux is not installed, the extension says so and links to the download page.

## What the extension does besides { #what-it-does }

Right-click an identifier in a Verilog, SystemVerilog or VHDL file and choose **What Drives This? (NetCrux)**:

1. The extension takes your selection, or the word under the cursor.
2. It resolves the name to a hierarchical path through the design's stems index. When a bare name matches more than one path, it asks you which one you mean.
3. It sends the path to a running NetCrux desktop app, which highlights it on the schematic — see [Cross-probe & the suite](integrations.md#receive). NetCrux selects and frames the element, so a net that is off-screen or only a few pixels wide at fit zoom is brought into view.

If NetCrux is installed but not running, the extension offers to launch it. If it is not installed, the extension says so and links to the download.

The preview shows a netlist you already have. Elaborating Verilog, SystemVerilog or VHDL into a netlist, the Pro features and the other desktop-only features stay in the desktop app.

## Working with the other apps { #desktop }

Your VS Code window joins the suite's cross-probe network as **one** peer, however many of the EDACrux extensions you install:

- A desktop app can ask it to open a source file at a line, and the file opens in the editor.
- **EDACrux: Send Selection to Crux App** and **EDACrux: Highlight Selection in Crux App** send the identifier under your cursor to a running EDACrux app. With one app connected it goes there directly; with several you pick one.

Cross-probing works between apps on the same machine. The walkthrough in [Cross-probe from a waveform](cookbook/cross-probe-from-waveform.md) shows the same round trip between the desktop apps.

## Commands, settings and telemetry { #reference }

The extension's listing on the [Marketplace](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.netcrux) has the full list of commands and settings. The extension sends usage statistics only while VS Code's own telemetry setting is on. From 1.1 it sends nothing in the EEA, the United Kingdom, Switzerland or South Korea, whatever that setting says, and it keeps no installation ID while it is not sending.
