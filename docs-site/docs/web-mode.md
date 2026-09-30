# Web viewer

NetCrux builds for the browser (`flutter build web`), and a build is
deployed at `app.netcrux.app`; the static bundle is also self-hostable.
The browser cannot spawn Yosys, GHDL, or any other subprocess, so the web
build is **strictly read-only**: the design is a *pre-elaborated* Yosys
JSON document, and the browser renders the schematic, hierarchy and
inspector on top of it.

## Loading a netlist {#loading}

There are two ways in.

### 1. Open a file {#upload}

The start screen's **Open Netlist JSON…** button — also on the toolbar and
in the command palette — picks a `.json` netlist from your machine. The
file is read inside the page and never uploaded anywhere; the tab is named
after it.

### 2. A URL {#url}

```
https://app.netcrux.app/?json=<encoded-url>
```

`<encoded-url>` is a `Uri.encodeComponent`-encoded URL of a JSON
document the browser can fetch. NetCrux fetches it on load, opens it in a
tab named after the document, and renders the schematic.

CI artefacts, GitHub release assets, and GitHub Pages-hosted JSONs
all work. The server has to allow the viewer's origin to fetch it: a
self-hosted artefact server must send `Access-Control-Allow-Origin: *`
(or the viewer's origin), and a page served over HTTPS can only fetch
HTTPS. When the fetch fails, the tab shows the error and a message says
the server must allow cross-origin requests.

### Deep-link hints {#fragment}

After the JSON loads, the URL fragment is consulted for
auto-navigation:

| Fragment field | Effect |
|----------------|--------|
| `#scope=top.cpu.alu` | Open the named scope — the dotted path the breadcrumb shows, starting with the top module. |
| `#sig=alu_y` | Select the named net or cell and centre the canvas on it. It is looked up in the `#scope=` scope first, then anywhere in the design; a net is revealed at the cell that drives it. |

Both can appear together (`#scope=top.cpu&sig=alu_y`). The fragment is
*not* sent to the network — it's metadata for the in-page state. A hint
that names nothing in the design is ignored and the design opens at its
root.

## Generating the JSON

Yosys's `write_json` produces the format NetCrux expects. Run on a
desktop / CI machine:

```bash
yosys -p 'read_verilog top.v sub.v; hierarchy -check -top top; proc; write_json top.json'
```

For mixed Verilog + VHDL designs, lower the VHDL to Verilog with a plain
GHDL first — the same approach the desktop app uses, with no GHDL Yosys
plugin involved:

```bash
ghdl --synth --out=verilog sub.vhd -e sub > sub_ghdl.v
yosys -p 'read_verilog top.v sub_ghdl.v; hierarchy -check -top top; proc; write_json top.json'
```

Commit `top.json` to a public artefact server and point the URL
at it.

## Features available in web mode

- Hierarchy browser, push-in / pop-out scope navigation
- Schematic canvas with pan / zoom and LOD banding
- Selection + inspector (cell properties, net driver / sinks)
- Search (substring, glob and regex over instance, cell and net names)
- One-step fanin / fanout tracing (within the loaded document)
- App settings (theme, language, keymap), persisted in the browser's
  local storage

## Features that are NOT in web mode

The following are gated to desktop because they require a local
subprocess, file watcher, or file system:

- **Yosys / GHDL elaboration** — the browser cannot spawn the
  toolchain. Web mode renders pre-elaborated JSON only.
- **Auto-reload on file change** — no file watcher in the browser.
  Reload the page to fetch a newer JSON.
- **Opening sources, projects and filelists** — each needs a local file
  path and a Yosys run, neither of which a browser has, so the browser
  build does not offer them.
- **Sessions, named workspaces and exports** — these read and write files
  through the desktop file system, which the browser build does not have,
  so their commands are not offered either. The workspace is not
  auto-saved between visits.
- **Pro features** — the web build is Open Core only; Pro commands are not
  offered in the browser.
- **CXP cross-probing** — the cross-probe protocol uses TCP loopback
  sockets, which a browser cannot open, so the Cross-Probe panel is not
  offered. Web peers would need a WebSocket bridge; none exists. See the
  [CXP integration guide](integrations/cxp.md).
- **Update banner** — the update check runs on web (for its server-time
  watermark) but the banner never renders there, and **Check for Updates**
  is not offered. See
  [Updates, issues & privacy](user-guide/updates-and-feedback.md).
- **Command-line arguments** — the web build skips the CLI surface
  entirely.

## Deployment target

The web build is deployed as a static bundle to `app.netcrux.app`
(Cloudflare Workers Static Assets, configured by `wrangler.jsonc` in the
repository).
`viewer.netcrux.app` is a separate, hand-written demo on the marketing
site, not this build.

## Build instructions (self-hosting)

```bash
cd netcrux
flutter pub get
flutter build web
# build/web/ now contains a self-contained static bundle.
# Serve it behind any HTTP server:
cd build/web && python3 -m http.server 8080
# Open http://localhost:8080, or http://localhost:8080/?json=<encoded-url>
```

The bundle is plain static HTML / JS — no service worker
registration is required (the build emits one but it is optional).
