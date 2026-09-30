# Use in VS Code

The **NetCrux extension** lets you ask "what drives this signal?" from the VS Code editor, with the cursor already on the identifier, and answers it in a running NetCrux schematic.

It installs from the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.netcrux) and from [Open VSX](https://open-vsx.org/extension/ferrite-engineering/netcrux), which is where Cursor, Windsurf, VSCodium and Theia install from. To install all four EDACrux extensions at once, install the [EDACrux Suite](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.edacrux) pack.

## What it does { #what-it-does }

Right-click an identifier in a Verilog, SystemVerilog or VHDL file and choose **What Drives This? (NetCrux)**:

1. The extension takes your selection, or the word under the cursor.
2. It resolves the name to a hierarchical path through the design's stems index. When a bare name matches more than one path, it asks you which one you mean.
3. It sends the path to a running NetCrux desktop app, which highlights it on the schematic — see [Cross-probe & the suite](integrations.md#receive).

If NetCrux is installed but not running, the extension offers to launch it. If it is not installed, the extension says so and links to the download.

The extension does not draw schematics itself: the schematic, its layout and your elaborated design stay in the desktop app.

## Working with the other apps { #desktop }

Your VS Code window joins the suite's cross-probe network as **one** peer, however many of the EDACrux extensions you install:

- A desktop app can ask it to open a source file at a line, and the file opens in the editor.
- **EDACrux: Send Selection to Crux App** and **EDACrux: Highlight Selection in Crux App** send the identifier under your cursor to a running EDACrux app. With one app connected it goes there directly; with several you pick one.

Cross-probing works between apps on the same machine. The walkthrough in [Cross-probe from a waveform](cookbook/cross-probe-from-waveform.md) shows the same round trip between the desktop apps.

## Commands, settings and telemetry { #reference }

The extension's listing on the [Marketplace](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.netcrux) has the full list of commands and settings. The extension sends usage statistics only while VS Code's own telemetry setting is on.
