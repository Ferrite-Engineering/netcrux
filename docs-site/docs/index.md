# Welcome to NetCrux

NetCrux is an interactive RTL schematic browser and signal tracer. It turns Verilog, SystemVerilog and VHDL into a navigable schematic — pan and zoom, push into modules, click a net to see what drives it and what it feeds. This guide is written for people who already read RTL for a living: it is precise about what each feature does, the elaboration toolchain involved, and the keyboard you will actually use.

!!! tip "New here?"

    Start with [Installation & first elaboration](getting-started.md), then take the [interface tour](interface.md). If you are coming from `yosys show` or Verdi, jump to [Navigating the schematic](navigating.md) and [Tracing signals](tracing.md). Prefer to learn by doing? The [Cookbook](cookbook.md) walks through complete workflows step by step.

## What it does

- **Push-in / pop-out navigation** through the module hierarchy, with a clickable breadcrumb.
- **Three-band level-of-detail rendering**, so the canvas stays smooth from full symbols down to thousand-cell overviews.
- **Selection and inspector** showing cell type, parameters, ports and net details.
- **One-step fanin / fanout tracing** with ++bracket-left++ and ++bracket-right++ — drivers or loads highlighted, everything else dimmed.
- **Design search** over instance, cell and net names in every scope, in substring, glob or regex mode.
- **Sessions, projects and workspaces**, Vivado `.f` filelist import, and PNG / SVG / JSON export of the current scope.
- **Auto-reload** when a source file changes on disk.
- **Cross-probe (CXP)** with WaveCrux, LintCrux and SimCrux.
- **Localized** in English, Simplified Chinese, Japanese and Korean.

## One app, four tiers {#tiers}

NetCrux ships as a single application. The free **Open Core** browser is complete on its own; **Pro** and **Enterprise** add capability on top without changing anything you already use, and **Education** grants the Pro feature set free to verified students and educators. This documentation covers all four. Wherever a feature requires a paid tier, you will see a badge next to its name:

| Badge | Meaning |
|---|---|
| *(no badge)* | Open Core. Free and open. No account, no license key, no time limit. |
| <span class="tier tier-pro">Pro</span> | Pro tier. Cone of influence, X-Trace, netlist diff, custom symbols, the RTL source pane, CDC, reset-domain and FSM analysis, and cross-probing from the schematic context menu. |
| <span class="tier tier-enterprise">Enterprise</span> | Enterprise tier. Collaborative schematic sessions (on your local network or over the internet), org-wide symbol libraries, org-wide policy from a signed configuration file, and the audit log. The centralized source server is not built; see [tiers & licensing](https://edacrux.app/licensing#editions). |
| <span class="tier tier-edu">EDU</span> | Education tier. Every Pro feature, free for verified students and non-commercial use. |

The NetCrux download includes the Pro and Enterprise features; a build of the open-source `netcrux` repository contains Open Core only.

!!! note "What the badges mean"

    The badges throughout the app and these docs tell you which tier a feature belongs to. Open Core is free and complete, and the Pro, Enterprise and Education features require a license. See [Tiers & licensing](licensing.md) for the full picture, including how the Education tier and license keys work.

## How this guide is organized {#map}

- [Installation & first elaboration](getting-started.md) — Download for Linux, macOS and Windows; the Yosys toolchain; open your first source files and watch the schematic appear.
- [The interface](interface.md) — The menu bar, toolbar, schematic canvas, hierarchy tree, inspector, diagnostics, command palette, tabs and split panes.
- [Appearance & themes](appearance-and-themes.md) — The six built-in color presets, per-token application-chrome overrides, and importing or exporting theme packs.
- [Keyboard & mouse reference](keyboard-mouse.md) — Every default shortcut, the schematic canvas keys, pointer and trackpad gestures, and how to rebind or export a keymap.
- [Tiers & licensing](licensing.md) — The four tiers and what each unlocks.
- [Updates, issues & privacy](user-guide/updates-and-feedback.md) — Update checks, the issue reporter, and usage statistics.
- [Sources, projects & sessions](files-and-projects.md) — Input formats, `.netcrux-project` and `<design>.crux-project` files, filelist import, auto-reload, sessions, workspaces and export.
- [Navigating the schematic](navigating.md) — Push in and pop out, the breadcrumb, zoom and pan, level of detail, design search and the command palette.
- [Tracing signals](tracing.md) — One-step fanin and fanout, the Cone of Influence, and X-Trace.
- [Structural analysis](analysis.md) — Netlist diff, CDC and reset-domain analysis, FSM detection, and the switching-activity heatmap.
- [Inspector & RTL source](source-and-inspection.md) — The inspector panel, the RTL source pane, and the elaboration diagnostics panel.
- [Custom cell symbols](customizing.md) — The symbol manager, the three-tab symbol editor, the SVG sanitizer, and project versus user scope.
- [Bookmarks & annotations](bookmarks.md) — Pin names and notes to cells, nets and ports, and save them with the session.
- [Cross-probe & the suite](integrations.md) — The CXP cross-probe protocol with WaveCrux, LintCrux and SimCrux, plus Enterprise services.
- [Administration <span class="tier tier-enterprise">Enterprise</span>](administration.md) — For the person deploying NetCrux across a fleet: org-wide symbol libraries from your own share, the security model behind collaborative sessions and its limits, the audit events NetCrux records, and managed installs.
- [Cookbook](cookbook.md) — Task-driven recipes: trace a signal to its source, diff two revisions, triage a CDC crossing, make a custom symbol, and more.

## Conventions used in this guide {#conventions}

- Keyboard shortcuts are written for both platforms, macOS first: ++cmd+o++ / ++ctrl+o++. Where only one key is shown, it applies to all platforms.
- `Monospace` marks file names, formats, signal paths, Yosys types, menu paths, and anything you type.
- A <span class="tier tier-pro">Pro</span> or <span class="tier tier-enterprise">Enterprise</span> badge beside a heading means everything under it requires that tier.
- NetCrux is a desktop application for Linux, macOS and Windows. A read-only [web viewer](web-mode.md) at `app.netcrux.app` opens a pre-elaborated Yosys JSON netlist.

!!! note "Quick links"

    [Download NetCrux](https://netcrux.app/download) · [Pricing](https://netcrux.app/pricing) · [Open source](https://edacrux.app/open-source) · [CXP specification](https://edacrux.app/cxp)
