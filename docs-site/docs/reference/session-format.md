# Session file format (`.netcrux`)

A NetCrux session is a JSON document capturing one tab's view state. It is written by `File → Save Session As…` (++cmd+s++ / ++ctrl+s++) and read back by `File → Open Session…` (++cmd+l++ / ++ctrl+l++) into the active tab, or into a tab of its own by `File → Open Project…`, `netcrux --session <file>` and `netcrux <file>.netcrux`. For what sessions are for, see [Sources, projects & sessions](../files-and-projects.md#sessions).

```json
{
  "version": 2,
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
| `version` | Session schema version. NetCrux 1.1 writes `2` and reads `1` and `2`. See [Compatibility](#compatibility). |
| `sourceFiles` | The source paths to re-elaborate, as they were open in the tab. A single `.json` entry is a pre-built Yosys netlist, read back without elaboration. |
| `topModule` | The elaborated top at save time, used as the top module when the sources are re-elaborated. |
| `scopePath` | Instance names from the design root to the scope that was open. `[]` is the root, so `["cpu", "alu"]` is `top.cpu.alu`. |
| `zoom`, `panX`, `panY` | Canvas viewport. |
| `selection` | The primary selected element; absent when nothing was selected. See below. |
| `overlayMode` | `fanin` or `fanout`; absent when no trace overlay was showing. |
| `expandedScopes` | Expanded hierarchy-tree nodes, each an instance-name path joined with `/`. `""` is the root. |
| `annotations` | This tab's annotations, written only when non-empty. From NetCrux 1.1 every edition can author them. See below and [Annotations](../annotations.md). |

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

## Annotations {#annotations}

Each entry names its element with a `targetKind` (`cell`, `port`, `boundaryPort`, `net` or `scope`) and a `targetId` in the canvas's own id shapes: a cell instance name, `<cell>:<port>` for a pin, `port:<name>` for a boundary port, a wire's `e_<netId>_<k>` edge id for a net, and a dotted instance path for a scope.

```json
"annotations": [
  {
    "id": "an-1759780000000-0",
    "targetKind": "cell",
    "targetId": "$procdff$17",
    "title": "State register",
    "body": "Check the reset value",
    "createdAtMillis": 1759780000000,
    "updatedAtMillis": 1759780000000,
    "moduleName": "fsm_lock"
  },
  {
    "id": "an-1759780000500-1",
    "targetKind": "cell",
    "targetId": "$procdff$17",
    "body": "Resets to **IDLE**, not LOCKED.",
    "createdAtMillis": 1759780000500,
    "updatedAtMillis": 1759780000500,
    "author": "me",
    "moduleName": "fsm_lock"
  }
]
```

| Field | Meaning |
| --- | --- |
| `id` | Opaque id, unique within the session. |
| `title` | From NetCrux 1.1: the annotation's one-line title; absent when it has none. |
| `body` | The annotation's Markdown text; empty when it has only a title. An annotation has a title, a body, or both. |
| `author` | Optional author; absent when unattributed. |
| `createdAtMillis`, `updatedAtMillis` | Milliseconds since the Unix epoch. |
| `moduleName` | The module of the scope the element was annotated in. Element ids are local to a module, so this says which module's `u_fifo` is meant. Absent in entries written before NetCrux recorded it; those are matched by id in whichever scope is open. |
| `sessionLayerId`, `sessionLayerLabel` | From NetCrux 1.1: the collaborative session an annotation was written in, and that session's label. Annotations with the same layer are grouped in the Annotations panel and hidden or deleted together. Absent for a note written outside a session. |
| `authorId` | From NetCrux 1.1: the session participant who wrote a note that belongs to somebody else. Such a note can be hidden or deleted but not edited. Absent for your own notes. |
| `colorArgb` | From NetCrux 1.1: the author's colour when the note was written in a session, as a 32-bit ARGB integer, kept fixed so the note does not change colour in later sessions. |
| `hidden` | From NetCrux 1.1: `true` while the note's layer is hidden from the schematic; absent otherwise. |

An entry with a missing required field or an unknown `targetKind` is skipped and the rest of the session loads.

Older files may contain `bookmarks`; NetCrux reads them as annotations.

## What loading restores

Loading re-elaborates `sourceFiles` with `topModule` as the top and restores the tab's annotations straight away, replacing the ones the tab had. Once the design has elaborated it opens `scopePath`, expands `expandedScopes`, restores `selection`, and reinstates `zoom` / `panX` / `panY` when that scope is laid out, in place of the usual fit-to-view.

- A `scopePath` that no longer resolves leaves the tab at the root, fitted to the view.
- Element ids in `selection` that the re-elaborated design no longer has select nothing.
- When elaboration fails, the tab shows the error; the selection and camera are still applied, and the scope and expanded rows are not.

The trace overlay is never re-applied: `overlayMode` is informational, so press ++bracket-left++ or ++bracket-right++ again.

## Compatibility {#compatibility}

Unknown fields are **tolerated** on load, so a session written by a newer NetCrux at a version this build reads still parses: you lose the fields the older build does not understand, and nothing else.

NetCrux 1.1 writes version `2` and reads versions `1` and `2`. A `version` the build does not recognize is **rejected** with a clear error rather than partially loaded, so NetCrux 1.0, which reads only version `1`, does not open a session saved by NetCrux 1.1.

Sessions do not embed your RTL. They reference source paths, so a session is only meaningful on a machine that can see those files.
