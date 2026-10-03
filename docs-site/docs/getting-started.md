# Installation & first elaboration

NetCrux is a desktop application for Linux, macOS and Windows. It does not synthesize or simulate — it drives **Yosys** as a subprocess to elaborate your RTL, lays the result out with ELK, and renders an interactive schematic. There is no account to create and no license key to enter before you elaborate your first design. This page covers how to get the app, how the toolchain fits together, and how to open your first source files.

## Platforms {#platforms}

| Platform | Versions | How you get it |
|---|---|---|
| Linux | x86_64 | AppImage or `.tar.gz` from the [downloads page](https://netcrux.app/download). |
| macOS | Universal (Intel + Apple Silicon), macOS 12.0 or later | From the [downloads page](https://netcrux.app/download). |
| Windows | Windows 10 / 11, x86_64 | Installer or `.zip` from the [downloads page](https://netcrux.app/download). |
| Web | Any modern browser | A read-only viewer at `app.netcrux.app` for a Yosys JSON netlist you already have. See [Web viewer](web-mode.md). |

NetCrux is localized in English, Simplified Chinese, Japanese and Korean. The **Language** picker is in `Settings → Appearance`.

### Building from source

The Open Core app builds from the open-source `netcrux` repository with the Flutter SDK; the repository README has the full instructions:

```bash
git submodule update --init --recursive   # crux-shared
flutter pub get
flutter run -d macos                      # or -d linux, -d windows
```

## How Yosys is used under the hood {#toolchain}

NetCrux does not implement an HDL front end. It shells out to **Yosys**, which runs `read_verilog` for Verilog and SystemVerilog and writes the elaborated netlist as Yosys JSON; NetCrux reads that JSON and renders it. The script it builds is roughly:

```text
read_verilog [-I inc]… [-D def]… "file.v"…
read_verilog -sv …
hierarchy -check [-top <name> | -auto-top]
proc
write_json <temp>
```

The JSON is read back and the temporary file deleted. Results are cached, so re-opening the same sources with the same include paths and defines skips Yosys entirely.

VHDL is lowered to Verilog first: NetCrux runs `ghdl --synth --out=verilog <vhdl files> -e <top>` as a separate process and hands the emitted Verilog to Yosys. You need `ghdl` on your `PATH` and nothing else — no `ghdl-yosys-plugin`, and no plugin-capable Yosys build. GHDL elaborates the top unit named by the project's top module; VHDL files opened without a project that names one are elaborated with the entity name `top`. GHDL is GPLv2 and is invoked as a separate program, never linked in.

### The layout engine {#layout-engine}

The elaborated netlist is laid out by the **Eclipse Layout Kernel**. On desktop NetCrux runs a native port of it, built into the app, so a scope of a few thousand cells lays out in well under a second on Linux, macOS and Windows alike and needs a fraction of the memory the JavaScript build did. The web edition runs the JavaScript build, elkjs, in the browser's own engine.

The JavaScript build also ships inside the desktop app as a fallback. NetCrux prints the engine it started on stderr when the first layout of a tab begins (`netcrux: layout engine: native (elkrs …)`), and setting `NETCRUX_LAYOUT_ENGINE=elkjs` in the environment keeps elkjs for a comparison; on the fallback, a scope past roughly a thousand cells can take minutes, and on Windows, where the fallback runs on an interpreter, it may hit the layout timeout.

A scope that exceeds the timeout, which grows with the scope's size from two minutes up to twenty, reports "layout timed out". Selecting another scope abandons a solve you are no longer waiting for.

### Install Yosys {#install-yosys}

**NetCrux does not ship Yosys.** Install it yourself and make sure `yosys` (`yosys.exe` on Windows) is on your `PATH`.

| Platform | Typical install |
|---|---|
| Linux | `apt install yosys`, or [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) |
| macOS | `brew install yosys`, or OSS CAD Suite |
| Windows | `winget install YosysHQ.Yosys`, or OSS CAD Suite |

Without Yosys, elaboration fails with *"Yosys could not be found or run. Install Yosys, or set its path in Settings → Engines."* and the status bar shows **Yosys not found**.

### Pointing NetCrux at a specific Yosys {#yosys-path}

Three ways, in precedence order:

1. `--yosys-path /opt/oss-cad-suite/bin/yosys` on the [command line](cli/usage.md) — wins for that launch.
2. `Settings → Engines → Yosys binary path` → **Custom**, then an absolute path in **Yosys executable path**. NetCrux runs the binary as you type and shows **Detected:** and the version under the field, or the reason it could not run. Open Settings with ++cmd+comma++ / ++ctrl+comma++.
3. `Settings → Engines → Yosys binary path` → **Auto-detect** (the default) — the operating system resolves `yosys` against `PATH`.

These choose Yosys only. GHDL always resolves from `PATH`.

!!! note "The Bundled option resolves nothing today"

    `Settings → Engines` also offers **Bundled**. No Yosys or GHDL binary ships inside the NetCrux download, so this mode finds a binary only when the `NETCRUX_BUNDLED_BIN_DIR` environment variable points at a directory holding `<platform>/yosys` and `<platform>/ghdl` (`<platform>` is `linux-x86_64`, `macos-universal` or `windows-x86_64`), and otherwise falls back to the `PATH` lookup.

## First launch {#first-launch}

With nothing open, the canvas shows the welcome screen: **Welcome to NetCrux**, the version, your **Recent projects** and **Recent source files** (and recent workspaces, once you have saved one), a **Clear recent** button, and the **Open Project…**, **Open Source Files…** and **Open Workspace…** buttons. You do not need a design loaded to explore the app — the menu bar, toolbar, command palette and Settings all work from the welcome screen.

## Elaborate your first design {#first-elaboration}

1. **Open your source files.**

    Choose `File → Open Source Files…` (++cmd+shift+o++ / ++ctrl+shift+o++) and pick one or more `.v`, `.sv`, `.svh`, `.vh`, `.vhd` or `.vhdl` files, or `File → Open Project…` (++cmd+o++ / ++ctrl+o++) to open a saved `.netcrux-project`. From a shell, `netcrux rtl/top.v rtl/alu.v` opens each file in its own tab.

2. **Let NetCrux detect the language.**

    The language comes from the file extension — you do not choose Verilog versus VHDL by hand. `.vhd` and `.vhdl` go through GHDL; `.sv` and `.svh` are read as SystemVerilog; `.v` and `.vh` as Verilog.

3. **Read the schematic.**

    Yosys elaborates, NetCrux lays out the top module with ELK, and the schematic appears on the canvas. The hierarchy tree on the left mirrors it and the status bar shows the first source file, the top module and the design's cell count. From here, double-click an instance to push in, or select a net and press ++bracket-left++ / ++bracket-right++ to trace it, then ++z++ to frame the trace. To find a cell by name, type it in the hierarchy tree's filter.

To try NetCrux before pointing it at your own RTL, open one of the projects under `examples/` in the `netcrux` repository with `File → Open Project…`.

Supported inputs:

| Input | How it loads |
|---|---|
| Verilog (IEEE 1364-2005), SystemVerilog (IEEE 1800) | Elaborated by Yosys `read_verilog`. |
| VHDL (IEEE 1076) | Lowered to Verilog by `ghdl --synth`, then read by Yosys. |
| `.netcrux-project` | A JSON project file: source list, top module, include directories and defines. |
| `<design>.crux-project` | The suite design manifest. See [Sources, projects & sessions](files-and-projects.md#crux-project). |
| `.f` filelist | A Vivado-style filelist. Import with `File → Import Vivado Filelist…` (++cmd+i++ / ++ctrl+i++). |

The full story on projects, auto-reload, sessions, workspaces and export lives on [Sources, projects & sessions](files-and-projects.md).

!!! warning "Elaboration errors surface in Diagnostics"

    If Yosys cannot run, times out, or exits with an error — a syntax error, an unresolved module, a VHDL file GHDL cannot lower — the canvas shows the reason and the **Diagnostics** panel (++cmd+3++ / ++ctrl+3++) lists the parsed errors and warnings with their `file:line`. See [Inspector & RTL source](source-and-inspection.md#diagnostics).

## Staying up to date {#staying-up-to-date}

NetCrux checks a release manifest on launch, once a day while it is running, and when you switch back to the app. When a newer version is out, a strip appears above the app content — **View Changes** opens the changelog, **Update Now** opens the download page in your browser, and **✕** dismisses it. There is no in-app download and no self-update: NetCrux tells you, you decide.

Turn the automatic check off in `Settings → General → Automatically check for updates`. You can always check by hand from `Help → Check for Updates` (in the NetCrux application menu on macOS), the command palette, or the About box — the manual check runs even when the automatic one is off. The request is a plain fetch of a static manifest and carries nothing but your app version and operating system. Details in [Updates, issues & privacy](user-guide/updates-and-feedback.md#update-checks).

## Reporting issues {#reporting-issues}

The fastest way to get something fixed is the built-in issue reporter — open it from `Help → Submit Issue…`, the command palette, or the **Submit Issue…** button in the About box (++f1++). The report gathers your app version and build, platform, OS and locale; session state as counts and fixed vocabulary only (open tabs, whether Yosys was detected, source-file and module/cell/net counts, elaboration state, which analysis panes are open); the recent warning-and-error log; and, on desktop, an optional screenshot. Each category except the app and environment block is a toggle with a live preview of exactly what will be sent. Source-file paths, project paths, module/instance/net names and Yosys stderr are never included. Details in [Updates, issues & privacy](user-guide/updates-and-feedback.md#reporting-issues).

!!! note "Next steps"

    With a design elaborated, take the tour of [the interface](interface.md), learn the details of [sources, projects & sessions](files-and-projects.md), and then move on to [navigating the schematic](navigating.md).
