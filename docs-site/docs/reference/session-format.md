# Session file format (`.netcrux`)

A NetCrux session is a JSON document capturing one tab's view state. It is written by `File → Save Session As…` (++cmd+s++ / ++ctrl+s++) and read back by `File → Open Session…` (++cmd+l++ / ++ctrl+l++) into the active tab, or into a tab of its own by `File → Open Project…`, `netcrux --session <file>` and `netcrux <file>.netcrux`. For what sessions are for, see [Sources, projects & sessions](../files-and-projects.md#sessions).

```json
{
  "version": 1,
  "sourceFiles": ["/home/me/rtl/top.v", "/home/me/rtl/alu.v"],
  "topModule": "top",
  "scopePath": ["cpu", "alu"],
  "zoom": 1.25,
  "panX": -140.0,
  "panY": 32.5,
  "selection": { "kind": "cell", "cellId": "u_add" },
  "overlayMode": "fanout",
  "expandedScopes": ["", "cpu"]
}
```

## Fields

| Field | Meaning |
| --- | --- |
| `version` | Session schema version. Currently `1`. |
| `sourceFiles` | The source paths to re-elaborate, as they were open in the tab. A single `.json` entry is a pre-built Yosys netlist, read back without elaboration. |
| `topModule` | The elaborated top at save time, used as the top module when the sources are re-elaborated. |
| `scopePath` | Instance names from the design root to the scope that was open. `[]` is the root, so `["cpu", "alu"]` is `top.cpu.alu`. |
| `zoom`, `panX`, `panY` | Canvas viewport. |
| `selection` | The primary selected element; absent when nothing was selected. See below. |
| `overlayMode` | `fanin` or `fanout`; absent when no trace overlay was showing. |
| `expandedScopes` | Expanded hierarchy-tree nodes, each an instance-name path joined with `/`. `""` is the root. |
| `bookmarks`, `annotations` | Written only when non-empty. Authoring them is a Pro feature; Open Core builds keep them empty. See [Bookmarks & annotations](../bookmarks.md). |

## Selection

`selection` is one of:

```json
{ "kind": "cell", "cellId": "u_add" }
{ "kind": "port", "cellId": "u_add", "portId": "…", "portName": "A" }
{ "kind": "boundaryPort", "portId": "…", "portName": "clk" }
{ "kind": "wire", "edgeId": "e_42_0", "netId": 42, "edgeIdScheme": "per-net" }
```

A wire's `edgeId` is `e_<netId>_<k>`, where `k` numbers the wire among the driver-to-sink connections of its own net, so the id stays the same however the rest of the design changes. `edgeIdScheme` marks that numbering. A wire record without it was written by an earlier NetCrux, whose edge ids counted across the whole scope and may now name a different wire; loading it selects the first wire of its `netId` instead, which is the same net.

A multi-element selection writes the primary element at the top level and the rest under an `elements` array of the same shapes.

## What loading restores

Loading re-elaborates `sourceFiles` with `topModule` as the top and restores bookmarks and annotations straight away. Once the design has elaborated it opens `scopePath`, expands `expandedScopes`, restores `selection`, and reinstates `zoom` / `panX` / `panY` when that scope is laid out, in place of the usual fit-to-view.

- A `scopePath` that no longer resolves leaves the tab at the root, fitted to the view.
- Element ids in `selection` that the re-elaborated design no longer has select nothing.
- When elaboration fails, the tab shows the error; the selection and camera are still applied, and the scope and expanded rows are not.

The trace overlay is never re-applied: `overlayMode` is informational, so press ++bracket-left++ or ++bracket-right++ again.

## Compatibility

Unknown fields are **tolerated** on load, so a version-1 session written by a newer NetCrux still parses in an older one — you lose the fields the older build does not understand, and nothing else.

A `version` the build does not recognize is **rejected** with a clear error rather than partially loaded.

Sessions do not embed your RTL. They reference source paths, so a session is only meaningful on a machine that can see those files.
