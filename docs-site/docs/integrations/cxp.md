# CXP integration reference

**CXP** — the Cross-Tool eXchange Protocol — is how the EDACrux tools talk to
each other on your machine. Click a net in NetCrux and the matching
signal lights up in WaveCrux; ask WaveCrux to highlight a scope and
NetCrux navigates there. For the user-level overview, see
[Cross-probe & the suite](../integrations.md).

This page is the integration reference: the transport, the discovery
model, the exact message vocabulary NetCrux speaks, and the path formats
that make interop work. The protocol itself is specified at
[edacrux.app/cxp](https://edacrux.app/cxp).

## At a glance

| | |
| --- | --- |
| Transport | TCP, newline-delimited JSON, bound to `127.0.0.1` |
| Default port | `54323` (WaveCrux is `54322`, LintCrux `54324`, SimCrux `54325`) |
| Protocol version | `1.1` |
| Discovery | A shared per-peer manifest directory |
| Default state | **Enabled** |
| Scope | Localhost only. There is no remote or LAN mode. |

## Turning it on

`Settings → CXP Cross-Probe`:

- **Enable CXP server** — on by default. Cross-probe is a suite-defining
  capability and is meant to work without setup.
- **CXP port** — default `54323`, any value from 1 to 65535. The port is
  applied when you press Enter, and the server restarts on it.
- **Request attention on cross-probe** — on by default. Bounces the dock
  icon (or flashes the taskbar) when a peer's cross-probe is acted on. It
  never steals focus.
- **Broadcast selection automatically** — on by default. Announces your
  selection to connected peers as you select. When off, only explicit
  sends from the Cross-Probe panel go out.

The last two are disabled while the server is off. The same section shows
the server status (**Running on port 54323** or **Stopped**) and the
connected-peer count.

`Settings → Editors → Editor command (open source)` is the command NetCrux
runs when a peer asks it to open a source location. Default
`code -g {file}:{line}`. Tokens `{file}`, `{line}` and `{column}` are
substituted (`{column}` defaults to 1). Leave it empty to refuse
source-open requests.

Turning the server off, or changing the port, stops the server and removes
NetCrux's discovery manifest.

## Discovery

There is no service registry and no broadcast. Every Crux tool writes a
small JSON manifest into a **shared directory** and watches that
directory for its peers.

| Platform | Manifest directory |
| --- | --- |
| macOS | `~/Library/Application Support/crux/cxp/peers` |
| Linux | `${XDG_DATA_HOME:-~/.local/share}/crux/cxp/peers` |
| Windows | `%APPDATA%\crux\cxp\peers` |

Each file is `<peer_id>.json`:

```json
{
  "identity": {
    "peer_id": "netcrux-4711-1758210000000",
    "product_name": "netcrux",
    "product_version": "0.1.0",
    "capabilities": []
  },
  "host": "127.0.0.1",
  "port": 54323,
  "started_at": 1758210000000
}
```

NetCrux rewrites its manifest every 30 seconds as a liveness heartbeat,
scans the directory every 2 seconds, and prunes peers whose manifest has
gone stale for 5 minutes. Quitting the app does not delete the manifest;
peers drop it as soon as they see the process is gone (on Linux and macOS),
or when it goes stale (on Windows).

NetCrux **dials manifests that already exist**. It does not launch peers.
If WaveCrux is not running, nothing happens — start it and NetCrux picks
it up within a couple of seconds. Failed dials are retried every 5
seconds with backoff.

## Message vocabulary

CXP defines: `hello`, `hello_ack`, `goodbye`, `subscribe`,
`unsubscribe`, `notify_selection`, `request_highlight`,
`request_highlight_ack`, `request_open_source`,
`request_open_source_ack`, `request_open_artifact`,
`request_open_artifact_ack`, `error_response`.

Every message is one JSON object on one line:

```json
{"cxp_version":"1.1","message_id":"…","from":"netcrux-4711-…","kind":"notify_selection","payload":{…}}
```

A peer whose major version differs is refused: the server answers with an
`error_response` with code `unsupported_version` and closes the link. Minor
differences are accepted.

### What NetCrux sends

| Kind | When | Payload |
| --- | --- | --- |
| `hello` / `hello_ack` | Link setup | `identity` (plus `in_reply_to` on the ack) |
| `goodbye` | When NetCrux tears down a link it dialed | `reason` |
| `subscribe` | After the handshake on every link NetCrux dials | The non-control kinds: `notify_selection`, `request_highlight`, `request_open_source`, `request_open_artifact`, their acks, and `error_response` |
| `notify_selection` | Whenever the selection changes, while **Broadcast selection automatically** is on | `elements[]` (`{kind, path}`), `display_name`, and `metadata` carrying `netcrux.scope_path` and, with a design loaded, `crux.design_id` |
| `request_highlight` | When you press **Send selection to this peer** in the Cross-Probe panel | The selected element, `display_name`, `metadata` as above |
| `request_highlight_ack` | Reply to an inbound highlight | `in_reply_to`, `honored`, optional `reason` |
| `request_open_source_ack` | Reply to an inbound source-open | `in_reply_to`, `honored`, optional `reason` |
| `request_open_artifact_ack` | Reply to an inbound artifact-open | `in_reply_to`, `honored`, optional `reason` |

An empty selection is not broadcast, and a multi-select sends only the
primary element. NetCrux never sends `request_open_source`.

### What NetCrux receives and acts on

| Kind | Element kind | Effect |
| --- | --- | --- |
| `request_highlight` | `scope` | Walks the hierarchy tree and navigates to that scope. |
| `request_highlight` | `net` | Looks the net up by name in the current scope and selects the whole wire. |
| `request_highlight` | `instance`, `port` | Validated against the current scope's graph, then selected. |
| `request_highlight` | `signal`, or a `net` / `instance` / `port` that did not resolve exactly | Matches the last path segment against the current scope's nets, then boundary ports, then cells. |
| `request_highlight` | `source` | Opens the location with your configured editor command. |
| `request_highlight` | `marker`, `rule`, `test`, `breakpoint`, unknown | `honored: false` with a reason. Never throws. |
| `notify_selection` | first `signal` / `instance` / `port` / `net` that resolves | Selected exactly as for `request_highlight`. No ack — `notify_selection` is fire-and-forget. |
| `request_open_source` | — | `{file_path, line, column?}` handed to the editor command. |
| `request_open_artifact` | — | Only `artifact_kind: source` is accepted: NetCrux loads that file into the active tab. |

When an element does not resolve and the message carries a `crux.design_id`
that the suite's shared workspace maps to a design source, NetCrux opens
that design and acks `honored: true` with the reason
`opened design source from the shared workspace`.

Refusal reasons are returned verbatim, in English, and are worth knowing
when you are debugging an integration: `No active tab`, `No design loaded`
(scope requests only), `Scope <x> not found in current design`,
`Element <x> not found in current design`, `Could not resolve element
path`, `Unsupported element kind <kind>`, `No editor command configured.`,
`Editor exited with code <n>.`, `Failed to launch "<exe>": <message>`.

## Path formats — the interop contract {#path-formats}

This is the part another tool has to get right.

| Element kind | Canonical path |
| --- | --- |
| `instance` | `top.parent.cellName` (inbound also accepts a trailing `:cell`) |
| `port` | `top.parent.cellName.portName`; a boundary port is `top.parent.portName` |
| `net` | `top.parent.netName`; an anonymous wire is `top.parent:net:<edgeId>` |
| `scope` | `top.parent.cellName` |
| `source` | `file:///abs/path.v#L<line>[:C<column>]` |

A selected register or flip-flop cell is sent as a `net` named after its
output (the RTL register name), because that is the name a waveform carries.

NetCrux always **emits** `.` as the hierarchy separator. It **accepts**
both `.` and `/` on the way in. `source` paths are exempt from separator
normalization.

`display_name` is the net name for a named wire or a register, the cell id
for an instance, the port name for a port, and `net_<netId>` for an
anonymous wire.

## The Cross-Probe panel

`View → Show Cross-Probe Panel` (`Cmd/Ctrl+Shift+X`, or the toolbar button)
toggles the **Cross-Probe** dock tab. It shows:

- **Cross-probe server is offline.** when the server is not running.
- **Peers** — every discovered peer as product name and version over its
  peer id, each with a **Send selection to this peer** button that sends a
  `request_highlight` for whatever is selected right now. The button wears a
  **PRO** badge on its left in every edition: the targeted send is a Pro
  feature, and in Open Core pressing it opens the upgrade dialog and sends
  nothing.
- **Unreachable peers** — persistent warnings for peers that could not be
  reached.
- **Recent events** — a rolling log of the last 50 events: inbound messages,
  peer presence changes, and your panel sends. **Clear events** empties it.

!!! warning "What the event log does not show"
    Automatic `notify_selection` broadcasts are not logged. If a peer never
    appears, check `Settings → CXP Cross-Probe` for **Running on port 54323**
    and that nothing else holds that port.

## Walkthrough: NetCrux ↔ WaveCrux

1. Start both apps. Leave `Settings → CXP Cross-Probe → Enable CXP server`
   on in each.
2. In NetCrux, open the Cross-Probe panel (`Cmd/Ctrl+Shift+X`). Within a few
   seconds WaveCrux appears in the peer list.
3. Load a design in NetCrux and the matching trace in WaveCrux.
4. Click a net in the NetCrux canvas. NetCrux broadcasts a
   `notify_selection` with the canonical net path and the scope path in
   `metadata`.
5. From WaveCrux, ask NetCrux to highlight a scope. NetCrux navigates the
   hierarchy and acks `honored: true`; if the scope is not in the loaded
   design it acks `honored: false` with the reason.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No peers ever appear | Is the server enabled in both apps? Does the manifest directory exist and contain a `.json` per running app? |
| Peer appears, selections do not follow | Is **Broadcast selection automatically** on in the sending app? NetCrux acts on inbound `notify_selection` only when the element resolves in the current scope. |
| Highlight is refused | Read the `reason` on the ack — usually "No design loaded" or a path that does not exist in the current scope. |
| Source-open does nothing | `Settings → Editors → Editor command (open source)` is empty, or the command is not on `PATH`. The command is split on whitespace before `{file}` is substituted, and there is no shell or quoting — a file path with spaces is passed intact, but an editor executable path with spaces cannot be configured. |
| Works on desktop, not in the browser | Web builds cannot open TCP sockets. CXP is desktop-only. |
