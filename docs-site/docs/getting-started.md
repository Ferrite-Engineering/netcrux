# Installation & first elaboration

NetCrux is a desktop application for Linux, macOS and Windows. It does not synthesize or simulate — it drives **Yosys** as a subprocess to elaborate your RTL, lays the result out with ELK, and renders an interactive schematic. There is no account to create and no license key to enter before you elaborate your first design. This page covers how to get the app, how the toolchain fits together, and how to open your first source files.

## Platforms {#platforms}

| Platform | Versions | How you get it |
|---|---|---|
| Linux | x86_64; from NetCrux 1.1.1, glibc 2.28 or later (RHEL, Rocky Linux and AlmaLinux 8 and 9, Ubuntu 22.04 and later, Debian 12); before 1.1.1, glibc 2.34 | AppImage or `.tar.gz` from the [downloads page](https://netcrux.app/download), or `.deb` and `.rpm` for managed fleets. |
| macOS | Universal (Intel + Apple Silicon), macOS 12.0 or later | From the [downloads page](https://netcrux.app/download). |
| Windows | Windows 10 / 11, x86_64 | Installer or `.zip` from the [downloads page](https://netcrux.app/download). |
| Web | Any modern browser | A read-only viewer at `app.netcrux.app` for a Yosys JSON netlist you already have. See [Web viewer](web-mode.md). |

### Linux over a remote display {#linux-remote}

On a remote X session (VNC, X forwarding, ETX or NX) or a virtual machine without 3D support there is often no OpenGL. From NetCrux 1.1.1 the app checks for it at startup and, when there is none, draws with the software renderer and prints one line on stderr saying so; setting `FLUTTER_LINUX_RENDERER=opengl` keeps OpenGL. Before 1.1.1 the window stayed empty on such a display. NetCrux also needs the EGL and OpenGL ES libraries (`libEGL.so.1`, `libGLESv2.so.2`, from Mesa); the `.deb` and `.rpm` declare them from 1.1.1.

Such sessions often have no keyring service either. From NetCrux 1.1.1 a licence file or machine file still activates there: it is kept in a file only you can read, and the licence panel says where. A licence key needs a keyring, and the panel says so when there is none. A licence in your organization's policy file needs no keyring. See [Licensing](licensing.md).

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

### Which SystemVerilog the built-in reader reads {#systemverilog-subset}

Yosys's built-in `read_verilog -sv` reads the synthesizable core of SystemVerilog: `logic`, `always_ff` / `always_comb`, packed structs, enums and typedefs, packages declared at file scope, and interfaces in simple forms. It does not read every construct in IEEE 1800-2017. Three that current open cores use often stop it, although they are legal:

- a `return` statement in a function;
- a package import inside a module, in its header (`module m import p::*; #(...)`) or its body;
- a cast of a non-constant expression to a named type, such as `state_t'(x)` as a `case` expression.

When the built-in reader stops at one of these, NetCrux says which construct it was and that the design is not at fault. If your Yosys includes the [yosys-slang](https://github.com/povik/yosys-slang) front end (the OSS CAD Suite build does; Homebrew's does not), NetCrux reads the design again with `read_slang`, which handles the full language, and opens it. Otherwise install such a Yosys and point NetCrux at it in Settings, or convert the sources with [sv2v](https://github.com/zachjs/sv2v) first. A design read with `read_slang` draws each port connection as a buffer cell and an asynchronously reset flip-flop as `$aldff`.

VHDL is lowered to Verilog first: NetCrux runs `ghdl --synth --out=verilog <vhdl files> -e <top>` as a separate process and hands the emitted Verilog to Yosys. You need `ghdl` on your `PATH` and nothing else — no `ghdl-yosys-plugin`, and no plugin-capable Yosys build. GHDL elaborates the top unit named by the project's top module; VHDL files opened without a project that names one are elaborated with the entity name `top`. GHDL is GPLv2 and is invoked as a separate program, never linked in.

### The layout engine {#layout-engine}

The elaborated netlist is laid out by the **Eclipse Layout Kernel**. On desktop NetCrux runs a native port of it, built into the app, so a scope of a few thousand cells lays out in well under a second on Linux, macOS and Windows alike and needs a fraction of the memory the JavaScript build did. The web edition runs the JavaScript build, elkjs, in the browser's own engine; from NetCrux 1.2 it runs the same native port instead, compiled to WebAssembly and solving in a background worker, so a large scope lays out several times faster in a fraction of the memory, the page stays responsive while it does, and selecting another scope stops the solve. If the browser cannot load the WebAssembly engine, the web edition falls back to elkjs and says so in the browser console.

The JavaScript build also ships inside the desktop app as a fallback. NetCrux prints the engine it started on stderr when the first layout of a tab begins (`netcrux: layout engine: native (elkrs …)`), and setting `NETCRUX_LAYOUT_ENGINE=elkjs` in the environment keeps elkjs for a comparison; on the fallback, a scope past roughly a thousand cells can take minutes, and on Windows, where the fallback runs on an interpreter, longer.

While a scope lays out, the canvas shows how many cells it has, a progress bar, the time so far and a **Cancel** button. From NetCrux 1.2 the bar fills as the layout moves through its five phases, and the line under it names the phase: **Breaking feedback loops**, **Assigning cells to columns**, **Reducing wire crossings** (usually the longest), **Placing cells** and **Routing wires**. On the elkjs fallback the bar keeps sweeping, because elkjs reports no progress. **Cancel** stops the layout and shows **Layout stopped.** with a **Lay out again** button; selecting another scope, or entering or leaving a cone view, stops a layout you are no longer waiting for in the same way.

Before NetCrux 1.2 a layout had a time limit, from two minutes up to twenty depending on the scope's size, after which it reported "layout timed out". From NetCrux 1.2 there is no time limit: a large scope on a slow machine finishes however long it takes, and you decide when to stop waiting.

From NetCrux 1.2 a scope with more than 40,000 cells is not laid out when you open it, enter it or restore it. A flat post-synthesis scope of that size can take minutes and many gigabytes of memory to lay out whole, and a netlist of millions of gates has scopes of hundreds of thousands of cells. The canvas instead says how many cells the scope has and that it is too large to lay out whole, and offers two ways forward:

- Select a cell in the Hierarchy, or find one with [Search Design](navigating.md#search), then choose `View > Cone View` to see what drives it. A [cone view](tracing.md#cone-view) lays out only that neighbourhood, so it stays quick however large the scope is.
- Choose **Lay out anyway**. The button carries an estimate of the memory the whole layout needs (about 130 KB for every cell) and starts the usual layout, with its progress bar and **Cancel**.

The Hierarchy, Search, the Inspector and cone views all work on a scope that is waiting. Change the number under `Settings → Engines → Largest scope laid out automatically`: 20,000, 40,000, 80,000, 160,000 cells, or **No limit** to lay out every scope when it opens. What a layout costs depends on how the netlist is wired as well as on its size. On generated gate-level netlists, 21,000 cells took between 1 and 5 seconds and up to 1.9 GB, 42,000 cells between 2 and 16 seconds and up to 4.3 GB, and 84,000 cells between 5 and 60 seconds and up to 11 GB.

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

### The Yosys time limit {#yosys-time-limit}

NetCrux stops a Yosys run that takes too long, so a Yosys that has hung does not hold a tab forever. The time allowed grows with the size of the source files: 30 seconds at least, then about four minutes for every 64 MB of source. A five-million-gate structural netlist is 660 MB of Verilog; Yosys read and elaborated it in under seven minutes on a fast desktop, and NetCrux allows it 44 minutes, so a machine several times slower still finishes. Before NetCrux 1.2 the time allowed never exceeded ten minutes, whatever the size of the sources, which a multi-million-gate design on a slower machine could pass.

`Settings → Engines → Yosys time limit` changes it for the next elaboration: **Automatic** (the default), **Extended** (four times the automatic time) or **No limit** (Yosys runs until it finishes or you stop it). While Yosys runs, or while a large netlist file is being read, the canvas shows what is running, the Yosys pass and the time so far, with a **Cancel** button. **Cancel** stops Yosys, shows **Elaboration stopped.** and offers **Elaborate again**.

## First launch {#first-launch}

With nothing open, the canvas shows the welcome screen: **Welcome to NetCrux**, the version, your **Recent projects** and **Recent source files** (and recent workspaces, once you have saved one), a **Clear recent** button, and the **Open Project…**, **Open Source Files…** and **Open Workspace…** buttons. From NetCrux 1.2 the second list is called **Recent files**, each recent list has its own **Clear** button and a remove button on every entry, a file that has moved is greyed as **File not found** and is dropped when you click it, and `File → Clear Recent Projects` clears the projects list from the menu or the command palette. You do not need a design loaded to explore the app — the menu bar, toolbar, command palette and Settings all work from the welcome screen.

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
| Verilog (IEEE 1364-2005), SystemVerilog (IEEE 1800) | Elaborated by Yosys `read_verilog`, or `read_slang` where the built-in reader stops. See [which SystemVerilog it reads](#systemverilog-subset). |
| VHDL (IEEE 1076) | Lowered to Verilog by `ghdl --synth`, then read by Yosys. |
| `.netcrux-project` | A JSON project file: source list, top module, include directories and defines. |
| `<design>.crux-project` | The suite design manifest. See [Sources, projects & sessions](files-and-projects.md#crux-project). |
| `.f` filelist | A Vivado-style filelist. Import with `File → Import Vivado Filelist…` (++cmd+i++ / ++ctrl+i++). |
| `.lib` Liberty file (or `.lib.gz`) | A standard-cell library, for RTL that instantiates cells directly. See [Cell libraries](files-and-projects.md#cell-libraries). |

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
