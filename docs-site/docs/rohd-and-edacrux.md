# ROHD + EDACrux, from NetCrux 1.2

[ROHD](https://github.com/intel/rohd) is Intel's open-source hardware framework written in Dart. You describe hardware as Dart classes, simulate it in Dart, and generate SystemVerilog or a netlist from the same code. This page is for ROHD users. It shows how to get a ROHD design into NetCrux, what NetCrux does with it, and how NetCrux works with the other EDACrux apps on the same design.

!!! note "From NetCrux 1.2"

    Everything on this page is from NetCrux 1.2. An earlier NetCrux opens a ROHD netlist only as far as it is plain Yosys JSON, and does not use the structure and source locations ROHD adds. The Dart source locations need ROHD 0.7 or later, with source tracing on (below). The other EDACrux apps have the same kind of page: [WaveCrux](https://docs.wavecrux.app/rohd-and-edacrux), [LintCrux](https://docs.lintcrux.app/rohd-and-edacrux) and [SimCrux](https://docs.simcrux.app/rohd-and-edacrux).

## What NetCrux does with ROHD output

| You have | NetCrux | Where |
|---|---|---|
| ROHD's netlist JSON (an extended Yosys JSON) | Opens it directly, with no Yosys run and no Dart toolchain. Structure and array types, pack and unpack cells, and the Dart line that created each signal and instance are used, not skipped. | [Export the netlist](#export), [Open it](#open) |
| A synthesized, gate-level Verilog netlist made from ROHD's SystemVerilog | Reads it with the native gate-level reader, with no Yosys run and no JSON in between. | [Big designs](#big) |
| A netlist of any size | Opens it. Scopes of more than 40,000 cells wait to be laid out, and you open a Cone View of the part you care about. | [Big designs](#big) |
| A waveform, a lint finding or a test result from the other apps | Receives it over CXP and selects the matching element on the schematic. | [Cross-probe](#cross-probe) |

## Export the netlist from ROHD {#export}

Build the design, then write the JSON with `NetlistService`. To record where in your Dart code each signal and instance was created, activate the source tracer before the design is constructed and turn tracing on in the netlist configuration:

```dart
import 'dart:io';
import 'package:rohd/rohd.dart';

Future<void> main() async {
  SourceTracer.activate();                 // before any Logic or Module is created
  final top = MyDesign(Logic(), Logic());  // your top module
  await top.build();

  final netlist = NetlistService(
    top,
    configuration: NetlistSynthesizerConfiguration(
      trace: true,                         // record Dart source locations
      packageRoot: Directory.current.path, // paths are written relative to this
    ),
  );
  Directory('build').createSync(recursive: true);
  File('build/my_design.json').writeAsStringSync(netlist.json);
}
```

Run it from the root of your Dart package with `dart run`. Without `trace: true` (and `SourceTracer.activate()`) the netlist still opens, without the source locations. The format ROHD writes is described in `doc/netlist_json_format.md` in the ROHD repository; use a ROHD release that includes `NetlistService`.

## Open it in NetCrux {#open}

Any of these opens the file:

```bash
netcrux build/my_design.json
```

- `File → Open Netlist JSON…`, also on the toolbar.
- A design manifest that names it under `artifacts.netlist`. See [design manifests](files-and-projects.md#crux-project).
- The [web viewer](web-mode.md), which opens a netlist and nothing else.

NetCrux renders the top module as the schematic. The file is watched for changes like any source, so the schematic reloads when your Dart program writes it again.

### One file for the whole design {#manifest}

If you use more than one EDACrux app on the design, name everything once in a `<design>.crux-project` file next to your Dart package. Each app opens the part it owns, and all four derive the same design identity from it, which is what lets them cross-probe.

```yaml
# my_design.crux-project
version: 1
name: my_design

artifacts:
  netlist:    build/my_design.json   # NetCrux
  waveform:   build/top.vcd          # WaveCrux
  lint:       build/project.lintcrux # LintCrux
  simulation: simcrux.yaml           # SimCrux
```

Paths are relative to the manifest. Keep only the lines for the apps you use.

## What you see {#see}

- **Your types.** A structure or array port or net shows its type in the Inspector, for example `Sample{data:16, valid:1}` or `array[4]x8`.
- **Pack and unpack.** A `$struct_pack` or `$struct_unpack` cell is a box with one pin for each field, plus the whole value on one side.
- **Your procedural blocks.** A `Combinational` or `Sequential` block is a box with a pin for each signal it reads or writes. They are ROHD's own block types, so they are not reported as modules with no definition.
- **Your Dart source.** The Dart file, line and column that created a signal or an instance is the element's source location. An instance of a sub-module is located at the line that instantiated it. <span class="tier tier-pro">Pro</span> **Show Source for this Element** (right-click, the `Navigate` menu, or the command palette) opens that Dart file at that line in the [source pane](source-and-inspection.md#source-pane).

ROHD writes source paths relative to the package root you gave it, and the netlist does not record that root. NetCrux looks for each file beside the netlist and in each directory above it, up to eight levels, so a netlist written to `build/` in your package finds `lib/` above it. In the browser, which has no file system, the path is left as ROHD wrote it. [ROHD netlists](files-and-projects.md#rohd) has the full table of what NetCrux reads, and what it ignores.

## Big designs {#big}

A ROHD design that you synthesize ends as a gate-level netlist, and those get large. NetCrux 1.2 is built for that.

1. **Gate-level Verilog.** Generate SystemVerilog from ROHD, synthesize it with your flow, and open the structural Verilog the flow writes (`.v` or `.v.gz`). NetCrux reads it with the [native gate-level reader](files-and-projects.md#native-reader) instead of running Yosys on it. The reader is a beta feature in 1.2 and is on by default for the files it can read. If a file has anything the reader does not handle, NetCrux falls back to Yosys and says why in Diagnostics. To compare the two routes on one file:

    ```bash
    netcrux --netlist-reader=native route/top.v.gz
    netcrux --netlist-reader=yosys route/top.v.gz
    ```

2. **JSON of any size.** A Yosys or ROHD JSON file is read from disk in chunks, so a netlist of several gigabytes opens.
3. **Cone View.** A scope of more than 40,000 cells is not laid out when you open it. The canvas says how many cells the scope has, and you search for a cell and select it to see [what drives it](tracing.md#cone-view). The limit is `Settings → Engines → Largest scope laid out automatically`. See [The layout engine](getting-started.md#layout-engine).

## Cross-probe with the other apps {#cross-probe}

NetCrux, WaveCrux, LintCrux and SimCrux find each other on the same machine and talk over **CXP**, the cross-probe protocol. An element travels as a dot-separated hierarchical path such as `top.cpu.alu.result`, so every app means the same thing by the same name.

- Select a net in NetCrux and it highlights in a WaveCrux waveform of the same design. Select a signal in WaveCrux and it lights up on the NetCrux schematic. Walk through it in [Cross-probe from a waveform](cookbook/cross-probe-from-waveform.md).
- LintCrux and SimCrux send selections to NetCrux too. See [Cross-probe & the suite](integrations.md).
- If a name differs between the two files, the app that cannot find it says so and selects nothing. ROHD renames an instance called `reg` to `reg_` in its generated SystemVerilog and in its waveform, because `reg` is a SystemVerilog keyword.

### From your own Dart code, coming with EDACrux 1.2

A Dart package, `edacrux_cxp`, is coming with EDACrux 1.2. It is a pure-Dart CXP client with no Flutter dependency, so a running ROHD simulation or test can ask WaveCrux to show a signal and NetCrux to highlight a net. It is not published yet, so there is nothing to add to your `pubspec.yaml` today.

## Related

- [ROHD netlists](files-and-projects.md#rohd): the full list of what NetCrux reads from the file.
- [Gate-level netlists: the native reader](files-and-projects.md#native-reader)
- [Cross-probe & the suite](integrations.md) and the [CXP integration reference](integrations/cxp.md)
- [Use in VS Code](vscode.md)
- [Web viewer](web-mode.md)
