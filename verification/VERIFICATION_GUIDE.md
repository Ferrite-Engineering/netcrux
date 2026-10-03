# NetCrux (Open Core) — Verification Guide

> **Purpose.** Pre-release end-user verification reference for every Open Core NetCrux feature. Run the relevant sections before any tagged release. For a major release, run all sections.
>
> **Companion documents.**
> - `VERIFICATION_CHECKLIST.md` (sibling, this folder) — quick sign-off bullet list.
> - The Pro overlay's own verification guide. Pro builds **inherit every Open Core check**; that guide covers only the Pro/Enterprise delta.
>
> **Discipline.** This document grows alongside the implementation. Every user-visible open-core feature has a populated section here, and writing that section is a mandatory part of the same commit set that ships the implementation — see `CLAUDE.md` → "Verification Documentation Required."

---

## 1. How to use this document

### 1.1 Pre-release flow

1. Run §2 (fixture inventory) — confirm every fixture is present and current.
2. Run the per-feature sections corresponding to the features that changed since the last release.
3. Cross-check tier-gate scenarios for any feature that has been promoted into / out of a tier.
4. Sign off via §99.

### 1.2 Per-test format

Each test follows this structure:

- **What it does** — plain-language description of the feature, written for someone who is not yet an expert.
- **Setup** — what test data, configuration, or pre-conditions are needed.
- **Steps and expected behavior** — exact actions and what correct output looks like.
- **Diagnostics-assisted verification** — what to cross-reference in the diagnostics panel (once it exists per WaveCrux ARCHITECTURE.md §8.8).
- **Edge cases / break-it tests**.
- **Automation Assessment** — integration test / widget test / hybrid / manual. Reuse the WaveCrux coverage taxonomy.

### 1.3 Coverage status legend

Identical convention to WaveCrux's `wavecrux/verification/VERIFICATION_GUIDE.md` §1.4:

| Marker | Meaning | Pre-release human action |
|---|---|---|
| `[Coverage: UNIT]` | `flutter_test` unit test (models, services, providers, painters, golden snapshots) | Skip unless test file changed |
| `[Coverage: WIDGET]` | `flutter_test` widget/unit test with full `ProviderScope` | Skip unless test file changed |
| `[Coverage: INTEGRATION_TEST]` | Flutter `integration_test/` against a running app | Skip per platform once the integration test is green |
| `[Coverage: INTEGRATION_TEST — pending]` | Should be `integration_test/`, not yet implemented | **Run manually until the test lands** |
| `[Coverage: WIDGET — pending]` | Should be widget-tested, not yet implemented | **Run manually until the test lands** |
| `[Coverage: MANUAL]` | Inherently requires human judgement (UX, accessibility, visual polish) | **Always run during sign-off** |
| `[Coverage: HYBRID]` | Direction/threshold automated; absolute value requires human judgement | **Run the human portion at sign-off** |

---

## 2. Fixture inventory

All fixtures live under `verification/fixtures/` and are committed to the repo. Generation scripts live under `tool/`.

| Folder | Files | Purpose |
|---|---|---|
| _(none yet)_ | | A feature adds its fixture rows here when it lands |

---

## 3. Foundation

The foundation is the pipeline spine everything else stands on: the `NetlistModel` domain types, the Yosys elaboration pipeline (availability probe → runner → JSON parser → diagnostics), the ELK layout foundation, the theme system, and the app-shell scaffolding (keyboard shortcuts, command palette, file-open + recent files, CLI parsing, desktop hardening). Several runtime pieces have since migrated into the cross-suite `crux_yosys` package; the NetCrux-side providers are thin Notifiers over that API. The workspace shell superseded the original Welcome screen with the empty-canvas state (§4.1.6) — the file-open / recent-files / CLI plumbing verified here still backs it.

### 3.1 NetlistModel domain types — JSON round-trip and top detection

- **What it does.** The immutable domain layer (`lib/domain/models/netlist/`) that every downstream feature reads: `Module`, `Cell`, `Net`, `Port`, `BitRef` (sealed `NetBit` / `ConstantBit`), `PortDirection`, and `HierarchyNode`. Value equality, `copyWith`, and `fromJson`/`toJson` round-trip. Both Yosys top-attribute encodings (`'1'` and `'00000001'`) are detected as the top module.
- **Setup.** None — pure Dart, no Yosys.
- **Steps and expected behavior.**
  1. Load a design (any fixture) and inspect the hierarchy. Expected: the top module is auto-rooted (the `(* top *)` attribute is honored regardless of its bit-encoding).
  2. Round-trip a design through export-JSON → re-open (§4.8). Expected: identical module / cell / net / port structure.
- **Edge cases.** A `modules`-less JSON root surfaces a `FormatException`, not a crash. Constant bits (`ConstantBit`) and named net bits (`NetBit`) are distinguished in port bindings.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `NetlistModel` fromJson / topModule (both encodings) / toJson round-trip / value equality / copyWith | `[Coverage: UNIT]` (`test/domain/models/netlist/netlist_model_test.dart`) |
  | `Module` / `Cell` / `Net` / `Port` / `BitRef` / `PortDirection` / `HierarchyNode` per-type round-trip + equality | `[Coverage: UNIT]` (`test/domain/models/netlist/{module,cell,net,port,bit_ref,port_direction,hierarchy_node}_test.dart`) |
  | `modules`-missing → `FormatException` | `[Coverage: UNIT]` (`test/domain/models/netlist/netlist_model_test.dart`) |

### 3.2 Yosys elaboration pipeline — availability probe, runner, JSON parser, diagnostics

- **What it does.** The four-stage HDL→netlist pipeline. `YosysAvailabilityService` probes `yosys -V` through an injectable `ProcessRunner` and returns structured reason codes (`not_on_path` / `exec_failed` / `banner_unparsed`), surfaced to the UI via the keep-alive `yosysAvailabilityProvider`. `YosysRunner` spawns yosys with `-q -p <script>`, writes `write_json` to a temp file (avoiding log interleaving on stdout), and returns a sealed `YosysRunResult`; empty/missing JSON is a failure even at exit 0. `YosysJsonParser` decodes into `NetlistModel`, mapping every decode failure to a `YosysJsonParseException` with a one-line message and retained `cause`. `yosysErrorDiagnosticProvider` parses stderr into structured `YosysDiagnostic` records. The runtime for the probe / runner / diagnostic parser now lives in cross-suite `crux_yosys`; NetCrux keeps the Riverpod wrappers and the netlist-specific `YosysJsonParser`.
- **Setup.** A host with `yosys` on PATH for the live end-to-end path; the parse-only path needs no Yosys.
- **Steps and expected behavior.**
  1. Launch with Yosys absent from PATH. Expected: the availability provider reports unavailable with the `not_on_path` reason; the UI shows the elaboration-unavailable envelope (§4.1.7), never a raw exception.
  2. Open `test/fixtures/verilog/and2.v` with Yosys present. Expected: it elaborates, parses to a `NetlistModel`, and lays out.
  3. Open a design that emits Yosys warnings. Expected: the warnings reach the Tab Diagnostics drawer (§5.7) as structured rows.
- **Edge cases.** Exit-0-with-empty-JSON is treated as failure. Malformed / non-object / nested-type-error JSON surfaces as `YosysJsonParseException` (never a raw `toString`). Unparseable version banners return the `banner_unparsed` reason rather than throwing.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | Availability provider resolves the service result; not-found probe does not throw | `[Coverage: UNIT]` (`test/services/yosys/yosys_availability_provider_test.dart`) |
  | Runner provider wiring (spawn, temp-file JSON, empty-JSON-as-failure) | `[Coverage: UNIT]` (`test/services/yosys/yosys_runner_provider_test.dart`) |
  | JSON parser happy path + malformed-input → `YosysJsonParseException` | `[Coverage: UNIT]` (`test/services/yosys/yosys_json_parser_test.dart`); fuzz corpus `test/services/yosys/yosys_json_fuzz_test.dart` |
  | stderr → structured `YosysDiagnostic` record parsing | `[Coverage: UNIT]` (`test/services/yosys/yosys_diagnostic_provider_test.dart`) |
  | Full Verilog → yosys → parse → layout end-to-end | `[Coverage: INTEGRATION_TEST]` (`test/integration/verilog_pipeline_test.dart`, real-yosys group; skipped with a reason when yosys is absent) + `[Coverage: MANUAL]` (live open on a real host) |

### 3.3 ELK layout foundation — elkjs solve, buildElkInput, disk cache

- **What it does.** The layout half of the pipeline. `NetlistLayout` domain types (`BoundingBox`, `LayoutPoint`, `NodePosition`, `EdgeRoute`, `NetlistLayout`) mirror ELK's coordinate system so the renderer paints without axis flips. `ElkLayoutService` wraps elkjs via `flutter_js` (QuickJS) with the vendored `assets/elk/elk.bundled.js`; the pure `buildElkInput` converts a `Module` into ELK input JSON; a narrow `ElkJsHost` seam keeps the service unit-testable; all failures surface as `LayoutException`. Solves run on a background isolate and are served from two content-hash caches: a bounded in-session memory cache (LRU, capped at 16 entries / 64 MB of result-JSON size proxy, never evicting the entry just stored) and a disk cache that survives restarts.
- **Setup.** Desktop build (the isolate + flutter_js path); a design with a handful of cells.
- **Steps and expected behavior.**
  1. Open a design and navigate a scope. Expected: cells become boxes, ports become boundary nodes, nets route as edges; the schematic reads correctly with no flipped axes.
  2. Re-open the same scope (in-session or across restart). Expected: the cached layout returns instantly (no re-solve); `layout-cache/*.json.gz` appears under app-support.
  3. Walk a deep hierarchy, visiting more than 16 distinct scopes, then return to the scope you are currently viewing. Expected: it is still instant — the current scope is never the eviction victim. Returning to a long-ago scope may re-solve (evicted from memory) but is still served from the disk cache.
- **Edge cases.** A malformed / empty ELK input raises `LayoutException` (the same type on web, §5.1). High-fanout nets are skipped per the layout policy rather than exploding the solve.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `buildElkInput` conversion + `ElkLayoutService` solve + isolate offload + layout cache (incl. LRU entry-cap + byte-bound eviction and the never-evict-the-newest rule) + `LayoutException` mapping | `[Coverage: UNIT]` (`test/services/layout/elk_layout_service_test.dart`) |
  | `NetlistLayout` / `NodePosition` / `EdgeRoute` (modern `sections` + legacy `bendPoints`) / `BoundingBox` round-trip + equality | `[Coverage: UNIT]` (`test/domain/models/layout/*_test.dart`) |
  | Real flutter_js + elk bundle solve on a live host | `[Coverage: MANUAL]` — the unit tests stub `ElkJsHost`; §9.9 covers the live render. |

### 3.4 Theme system — Material 3 light/dark on the muted-amber seed

- **What it does.** `NetcruxTheme.dark()` / `NetcruxTheme.light()` build Material 3 `ThemeData` from the documented brand seed (`NetcruxColors.brandSeed = 0xFFD4A017`); `lib/core/theme/`. (The color-theme presets/overrides/packs surface lives in Settings → Appearance via `crux_theme`; see the suite-wide Color Theming section, §8.)
- **Setup.** Any build.
- **Steps and expected behavior.**
  1. Pick **Crux Light**, then **Crux Dark**, under Settings → Appearance → Presets; then press **View → Toggle Theme** (Cmd/Ctrl+Shift+K) twice. Expected: scaffold, panels, and chrome flip brightness live each time (`MaterialApp.themeMode` follows the active preset's brightness through `themeModeFromBrightness`); Toggle Theme switches any dark preset to Crux Light and Crux Light to Crux Dark.
  2. Confirm both themes derive from the amber seed (accent color family is consistent light↔dark).
- **Edge cases.** CJK locale sweep on chrome text must not overflow (covered per-widget elsewhere; §4.1.8).
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | Dark/light are M3 with the correct brightness; both derive from `brandSeed`; `brandSeed` is the documented amber | `[Coverage: UNIT]` (`test/core/theme/netcrux_theme_test.dart`) |
  | Toggle Theme activates the built-in preset of the opposite brightness (Crux Dark ↔ Crux Light, any other dark preset → Crux Light) | `[Coverage: WIDGET]` (`test/features/workspace/services/workspace_action_dispatcher_test.dart`) |
  | Live brightness flip repaints every surface | `[Coverage: MANUAL]` — see §8 (suite-wide theming). |

### 3.5 App-shell scaffolding — shortcuts, command palette, file-open, CLI parsing

- **What it does.** The interaction spine. `NetcruxAction` (implements `crux_shortcut_action`'s `CruxAction`) with platform-aware `defaultBindings()` (Cmd on mac/iOS, Ctrl elsewhere), driven through the text-input-aware `ShortcutManagerWidget`; `CommandPaletteDialog` wraps the cross-suite `CommandPalette<NetcruxAction>` and resolves labels via `L10N`; `FileOpenService` wraps `file_picker` (`.netcrux-project` / `.netcrux` for projects/sessions, HDL extensions for sources) and `AppSettings` records recent projects / sources (cap 12, dedupe-on-insert); `CliArgParser` returns a sealed `CliLaunchIntent`. Later sections extend each of these (multi-file CLI §4.1.5, palette reachability §4.1.11, shortcut conflicts §4.1.10).
- **Setup.** A desktop build; a few HDL files on disk.
- **Steps and expected behavior.**
  1. Press Cmd/Ctrl+Shift+P. Expected: the command palette opens and lists localized actions with per-row shortcut hints.
  2. Open a source file via the picker. Expected: it opens and is recorded in the recent-sources list (capped at 12, de-duplicated).
  3. Launch `netcrux path/to/design.v`. Expected: the CLI intent routes to opening that file.
- **Edge cases.** A picker failure surfaces a localized `filePickerFailed` snackbar (never a silent swallow). `--flag value` and `--flag=value` pairs are stripped from positional args.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `NetcruxAction` labels / categories / default bindings | `[Coverage: UNIT]` (`test/core/shortcuts/netcrux_action_test.dart`, `action_category_test.dart`, `shortcut_bindings_provider_test.dart`) |
  | `ShortcutManagerWidget` runtime dispatch (text-input aware) | `[Coverage: WIDGET]` (`test/core/shortcuts/shortcut_manager_widget_test.dart`) |
  | Command palette renders localized rows + tier badges | `[Coverage: WIDGET]` (`test/features/command_palette/widgets/command_palette_dialog_test.dart`) |
  | `CliArgParser` intent classification + flag stripping | `[Coverage: UNIT]` (`test/core/cli/cli_arg_parser_test.dart`) |
  | `FileOpenService` picker wrapping + recent-files record/dedupe/cap | `[Coverage: UNIT]` (`test/services/file_open/file_open_service_test.dart`) |

### 3.6 Desktop hardening — minimum window, UTIs, modal rule, menu bar

- **What it does.** The desktop-correctness bundle shared across the Crux suite: an 800×500 logical-pixel minimum window on all three desktop runners; macOS `CFBundleDocumentTypes` + `UTExportedTypeDeclarations` for every product extension (`.netcrux-project`, `.netcrux`, `.netcrux-workspace`, HDL sources, `.f`) so `file_picker`'s custom-extension flow and Finder Open-With work; the `openAdaptive` desktop-modal rule (no sliding-window full-screen routes on desktop); and `DesktopMenuBar` with platform-correct Quit/About placement.
- **Setup.** Native desktop builds on macOS, Windows, and Linux.
- **Steps and expected behavior.**
  1. Shrink the window to its minimum. Expected: it stops at 800×500; the multi-pane chrome stays usable.
  2. On macOS, double-click a `.netcrux-project` / `.v` in Finder (or use Open With…), once with NetCrux quit and once with it running. Expected: NetCrux opens the file in a tab, exactly as `netcrux <file>` on the command line would; a project whose `extraYosysCommands` name an unvetted command is refused with the same message. Select two files and open them together: each gets its own tab, in order. The Apple Event reaches Dart through `application(_:open:)` in `macos/Runner/AppDelegate.swift` and `IncomingDocumentService`; the document types alone only make Finder launch the app, which is how it once opened empty.
  3. Open Settings / About. Expected: a sized, scrollable modal over the visible workspace — not a sliding full-screen route.
  4. Inspect the menu bar. Expected: on macOS, About is in the application menu and Quit sits below a separator; on Windows/Linux, Quit is at the bottom of File and About is in Help.
- **Edge cases.** Two-finger trackpad scroll must reach inner scrollables inside the modal (ScrollConfiguration opts every `PointerDeviceKind` in). `allowedExtensions` passed to the picker must be a subset of the `Info.plist`-declared extensions or macOS silently rejects the file.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | Minimum window size / native UTIs | `[Coverage: MANUAL]` — native runner config; no Flutter-side test surface. |
  | Finder Open-With: an opened document is routed as the same path on the command line, cold and warm, and a refused project stays refused | `[Coverage: UNIT/WIDGET]` (`test/core/cli/cli_arg_parser_opened_document_test.dart`, `test/services/file_open/incoming_document_service_test.dart`, `test/features/workspace/screens/workspace_opened_document_test.dart`) + `[Coverage: STATIC]` (`test/static/macos_document_open_test.dart` — the runner still hands the event over) + `[Coverage: MANUAL]` step 2 — the Swift half runs only in a real app. |
  | `openAdaptive` renders a modal (not a route) on desktop; Settings shell | `[Coverage: WIDGET]` (`test/features/settings/screens/settings_screen_test.dart`) |
  | `DesktopMenuBar` category grouping + platform Quit/About placement | `[Coverage: WIDGET]` (`test/features/menu_bar/widgets/desktop_menu_bar_test.dart`) |
  | Live trackpad-scroll-through-modal + Finder integration | `[Coverage: MANUAL]` — inherently platform/human. |

## 4. Core Schematic Viewer

The "good enough to replace `yosys show`" milestone. Coverage is spread across the workspace shell (§4.1, which subsumed the original single-file viewer + Welcome screen), the seeded-design journey (§4.2, hierarchy + selection + inspector end-to-end), the elaboration cache (§4.3), and the per-feature sections below: schematic canvas navigation (§4.4), selection + inspector (§4.5), design search (§4.6), one-step tracing (§4.7), export (§4.8), session save/load (§4.9), the settings screen (§4.10), and auto-reload (§4.11). The command palette is covered under §4.1.11 and the empty-canvas welcome surface under §4.1.6.

## 4.1 Workspace + Multi-Tab + Split-Pane

NetCrux's adoption of the cross-suite `crux_workspace` package replaces the single-file viewer + Welcome screen pattern with the workspace-aware multi-tab + split-pane model.

### 4.1.1 Workspace auto-save and restore on launch

- **What it does.** The set of open tabs + panes + active selection auto-persists to `{appSupportDir}/workspace.json` on every mutation (debounced ~2 s) plus on `AppLifecycleState.paused` / `detached`. The next launch restores exactly that state — there is no "unsaved changes?" prompt class anywhere. The restore is gated on the **Restore tabs on launch** preference (§4.1.17), and a design already present in the restored document is not re-opened as a second tab (§4.1.16).
- **Setup.** Run a fresh build with no existing `workspace.json`.
- **Steps and expected behavior.**
  1. Launch NetCrux. Expected: empty-canvas state, "Welcome to NetCrux" headline.
  2. Open Project (or pick a recent project). Expected: a new tab appears in the active pane; the schematic canvas renders.
  3. Open a second project. Expected: a second tab appears alongside the first.
  4. Quit the app cleanly (or send it to background on Linux DE). Expected: no save prompts.
  5. Relaunch. Expected: both tabs are restored to the exact same state (active tab, scope, selection, viewport).
- **Diagnostics-assisted verification.** Inspect `{appSupportDir}/workspace.json` — `tabs` array has two entries with the correct `sourceFiles` payload; `activePaneId` points at the visible pane.
- **Edge cases.** A `workspace.json` with a future `version` integer is rejected via `WorkspaceSchemaVersionException`; the load path falls back to an empty workspace and logs the version mismatch. A tab opened from a `.netcrux-project` re-reads that file on restore, so its defines, include paths and extra Yosys commands apply (open `examples/cdc-capture/cdc-capture.netcrux-project`, relaunch, and confirm the elaboration matches a fresh open); if the file is gone, the tab falls back to its saved sources and top module.
- **Automation Assessment.** Project-file settings surviving a restore: `[Coverage: WIDGET]` (`test/features/workspace/screens/workspace_open_design_test.dart`). `[Coverage: INTEGRATION_TEST]` — `integration_test/workspace/restore_round_trip_test.dart` boots the real app, opens two tabs through the live notifier, forces the debounced auto-save to flush, and re-reads the persisted `workspace.json` through a fresh `WorkspaceService` to prove the next cold start restores both tabs. The per-mutation + corruption-recovery paths remain covered at the unit level by `test/services/workspace/netcrux_workspace_notifier_test.dart`. (The Flutter framework forbids a second `runApp` per process, so the literal quit/relaunch is approximated by the flush + fresh-service re-read — see `integration_test/PENDING.md`.)

### 4.1.2 Named workspace save / load

- **What it does.** `File → Save Workspace As…` writes the active workspace to a chosen `.netcrux-workspace` file. `File → Open Workspace…` (or `--workspace <path>` on CLI) reads one and replaces the active workspace after a single confirmation.
- **Setup.** Open two source-file tabs with distinct designs.
- **Steps and expected behavior.**
  1. From the command palette: Save Workspace As…, choose `/tmp/example.netcrux-workspace`. Expected: file written; no other state changes.
  2. Reset Workspace (palette command). Expected: empty-canvas state; both tabs gone.
  3. Open Workspace… → pick `/tmp/example.netcrux-workspace`. Expected: confirmation dialog (`workspaceLoadFromCliConfirm` string) → accept → both tabs return with the same active selection.
- **Diagnostics-assisted verification.** The recent-workspaces section on the empty-canvas state should now list the file. Workspace JSON is human-readable; opening it in a text editor shows the two tab payloads.
- **Edge cases.** A `.netcrux-workspace` with a corrupt payload silently falls back to `Workspace.empty()` and the framework logger surfaces the parse failure.
- **Automation Assessment.** `[Coverage: INTEGRATION_TEST]` — `integration_test/workspace/named_workspace_test.dart` drives the live `saveAs` → `resetWorkspace` → `loadFrom` notifier path (the same code the `File → Save/Open Workspace…` actions invoke) and asserts a `.netcrux-workspace` file round-trips both open tabs back into the workspace. The recent-list refresh UI remains `[Coverage: WIDGET — pending]`; CLI flag parsing is covered by `test/core/cli/cli_arg_parser_workspace_test.dart`.

### 4.1.3 Tab export as `.netcrux` session

- **What it does.** `File → Export Tab as Session…` writes the active tab as a single-tab session file (`.netcrux`). Opening a `.netcrux` adds it as a new tab in the current workspace.
- **Setup.** Open a project tab, then run the export action.
- **Steps and expected behavior.**
  1. Open a project. Expected: tab opens with the design.
  2. Export Tab as Session… → choose destination. Expected: file written.
  3. Open the exported `.netcrux` (via Open Project… picker which accepts both `.netcrux-project` and `.netcrux` extensions, or via CLI `--session <path>`). Expected: a new tab opens with the same payload.
- **Automation Assessment.** `[Coverage: INTEGRATION_TEST]` — `integration_test/session/session_export_round_trip_test.dart` boots the real app, seeds a design, navigates a real scope + cell selection + camera zoom/pan, exports through `SessionController.saveToPath` (the picker-free counterpart to `saveAs()` — the OS save dialog isn't automatable, see that method's doc comment), mutates the live state away from what was saved, re-opens through `SessionController.openByPath` (the same path-taking method `Open Session…` calls once the picker resolves a path), and asserts the scope / selection / camera state all come back exactly as saved.

### 4.1.4 Split-pane drag — tab between panes

- **What it does.** With two panes open, dragging a tab chip from one pane's tab bar onto the other pane reassigns the tab's `WorkspaceTab.paneId` and updates active-pane / active-tab pointers.
- **Setup.** Open two tabs in the active pane.
- **Steps and expected behavior.**
  1. Cmd/Ctrl+\ to Split Pane Right. Expected: the active tab moves into the new right pane; the left pane retains the remaining tab.
  2. Drag the right pane's tab back onto the left pane's tab bar. Expected: the tab returns to the left pane; the right pane is now empty.
  3. (Right pane empty → continue dragging.) Expected: the empty pane collapses back to single-pane after the next mutation that empties it (`closeTab` on the right pane's only tab, or per workspace invariants).
- **Automation Assessment.** `[Coverage: INTEGRATION_TEST]` for the `splitPaneRight` + `moveTabToPane` mutation contract end-to-end — `integration_test/workspace/split_pane_test.dart` boots the app, splits a pane, moves both tabs into the new pane, and asserts the emptied source pane collapses back to single-pane. The pointer-drag *gesture* mechanics (dragging a tab chip between tab bars) remain `[Coverage: WIDGET — pending]`. Unit contract still covered by `test/services/workspace/netcrux_workspace_notifier_test.dart`.

### 4.1.5 CLI multi-file open

- **What it does.** `netcrux a.v b.v c.vhd` opens each file as a **separate tab** in the active pane. `netcrux --session <path>` opens the session as a single new tab. `netcrux --workspace <path>` opens a named workspace, replacing the current one after a single confirmation.
- **Setup.** Build the desktop binary; have three small HDL files on disk.
- **Steps and expected behavior.**
  1. `netcrux a.v b.v c.vhd`. Expected: three tabs appear; the leftmost is the active tab; each tab's payload references one source file.
  2. `netcrux --session /tmp/example.netcrux`. Expected: one new tab opens at the existing workspace's active pane.
  3. `netcrux --workspace /tmp/example.netcrux-workspace`. Expected: single confirmation prompt before the workspace replaces the current one.
- **Edge cases.** Passing both `--workspace` and `--session` — workspace wins (CLI parser precedence). Passing a non-existent path — the open path surfaces a snackbar and the workspace is unchanged.
- **Automation Assessment.** `[Coverage: WIDGET]` for the parser precedence (`test/core/cli/cli_arg_parser_workspace_test.dart`). `[Coverage: INTEGRATION_TEST]` for the launch → multi-tab open path — `integration_test/tabs/cli_multi_file_test.dart` boots the real app with three source-file paths on the CLI and asserts three tabs open, one per file (Yosys-free; tab structure is asserted independent of elaboration).

### 4.1.6 Empty-canvas state

- **What it does.** When `workspace.tabs.isEmpty`, the app renders the empty-canvas state — recent projects + recent sources + recent workspaces lists + Open Project / Open Source Files / Open Workspace / New Tab buttons. Toolbar, status bar, menu bar, command palette, and Settings remain interactive.
- **Setup.** Fresh launch (or Reset Workspace).
- **Steps and expected behavior.**
  1. Launch. Expected: empty-canvas state renders. Settings is reachable via Cmd/Ctrl+,.
  2. Click Open Source Files. Pick two files. Expected: two tabs open (the empty-canvas state vanishes once `workspace.tabs.isEmpty` flips to false).
  3. Reset Workspace from command palette. Expected: a confirmation prompt → accept → return to empty-canvas state.
- **Locale sweep.** Switch between `en`, `zh_CN`, `ja`, `ko` via Settings. Expected: the title and section headers re-render in the target language with no overflow.
- **Automation Assessment.** `[Coverage: WIDGET]` (`test/features/workspace/widgets/empty_canvas_content_test.dart` covers all 4 locales + the layout) + `[Coverage: WIDGET]` (`test/widget_test.dart` covers the boot → empty-canvas render) + `[Coverage: INTEGRATION_TEST]` (`integration_test/workspace/empty_canvas_boot_test.dart` boots the real app via `bootstrap` with no args and asserts zero tabs + `EmptyCanvasContent` renders — also the harness smoke test).

### 4.1.7 Missing-file / missing-engine recovery on workspace restore

- **What it does.** If a tab's `sourceFiles` reference a path that has since been deleted or moved — or yosys itself is missing from PATH — the elaboration pipeline surfaces the failure across three surfaces simultaneously:
  - **Schematic canvas:** `SchematicErrorView` renders a **localized "Elaboration failed" envelope** — an error icon, the localized `elaborationErrorTitle`, and a localized per-failure body keyed off `LoadedNetlistException.kind` (`elaborationErrorYosysUnavailable` / `elaborationErrorTimeout({seconds})` / `elaborationErrorNonZeroExit({code})`, or `elaborationErrorGeneric` for anything unclassified — including a `LayoutException`). The raw detail (Yosys stderr, an unclassified error's text) is tucked into a collapsed **"Details"** expander (`elaborationErrorDetailsLabel`), so the envelope **never** renders `error.toString()` or leaks an exception class name. `currentLaidOutGraphProvider` rethrows `loadedNetlistProvider`'s error rather than swallowing it as `LaidOutGraph.empty`.
  - **Hierarchy panel:** when `state.model == null` AND `loadedNetlistProvider.hasError`, the panel renders a red `(!)` icon + `hierarchyEmptyElaborationFailed("<message>")` — distinct from the bare-empty `hierarchyEmptyNoDesign` placeholder, so the user can tell "I haven't opened anything" apart from "I opened something but it didn't elaborate."
  - **Diagnostics drawer (Cmd+3):** a top fatal-error banner shows `elaborationDiagnosticsFatal` + the exception's message + cause. Surfaces *before* any stderr-parsed Yosys diagnostics — used for failures where Yosys never ran at all (binary missing, source file absent, parse error before stderr existed).
- **Setup.** Two reproduction paths:
  - Missing source file: open a tab against `/tmp/test.v`, quit, delete `/tmp/test.v`, relaunch.
  - Missing engine: ensure `yosys` is NOT on PATH (`which yosys` returns empty), open any tab with valid sources.
- **Steps and expected behavior.** The tab restores → all three surfaces above light up with the failure message. The user can then File → Open Source Files… to replace the path, or Settings → Engines → Yosys to point at a custom binary.
- **Automation Assessment.** `[Coverage: WIDGET]` — `test/features/hierarchy/widgets/hierarchy_tree_panel_test.dart::surfaces elaboration error` covers the hierarchy banner; `test/features/project/providers/current_laid_out_graph_provider_test.dart::propagates LoadedNetlistException` covers the error propagating to the canvas; and `test/features/workspace/widgets/schematic_error_view_test.dart` covers the localized envelope itself — a 5-locale sweep (en / zh_CN / zh / ja / ko) asserting each `LoadedNetlistErrorKind` (yosysUnavailable / timeout / nonZeroExit) renders its localized body, the generic envelope covers unclassified errors, the class name never leaks, and the stderr detail stays collapsed until the "Details" expander is tapped. `[Coverage: INTEGRATION_TEST]` — `integration_test/tabs/missing_engine_recovery_test.dart` boots the real app, pins `yosysAvailabilityProvider` to `YosysAvailability.notFound` (deterministic on any host — no dependency on whether the CI/dev machine has Yosys on PATH) so `loadedNetlistProvider` settles on the real `LoadedNetlistException(kind: yosysUnavailable)`, then asserts all three surfaces recover cleanly in the same run: the canvas renders `SchematicErrorView` with the localized message, the hierarchy panel falls back to `hierarchyEmptyElaborationFailed`, and (after making the collapsed-by-default diagnostics pane visible via `panelLayoutProvider`) the Tab Diagnostics drawer's fatal-error banner shows the raw exception message. Exercises the identical fatal-error rendering path a missing-source-file failure (`LoadedNetlistErrorKind.nonZeroExit`) would hit downstream of the same `loadedAsync.hasError` branches.

### 4.1.8 Empty-canvas locale sweep

- **What it does.** All workspace strings — empty-canvas titles + section headers, tab-bar chip labels, split-pane menu items, workspace File menu items — round-trip cleanly through the en / zh_CN / zh / ja / ko ARB files.
- **Automation Assessment.** `[Coverage: WIDGET]` — `test/features/workspace/widgets/empty_canvas_content_test.dart` and `test/features/workspace/widgets/netcrux_viewer_tab_bar_strings_test.dart` cover all four supported locales.

### 4.1.9 Workspace-screen action dispatcher coverage

- **What it does.** Every entry in `NetcruxAction` routes through `_dispatchAction` in `lib/features/workspace/screens/workspace_screen.dart`. The dispatcher is the single source of truth for keyboard shortcuts, command-palette activation, and menu-bar selection — all three call the same handler.
- **Wired actions:** toggle panels, open settings / project / source files / workspace / search / about, zoom-in/-out, fit-all, pop-out/jump-to-top scope navigation, clear overlay, all six Pro openers (CoI fanin/out + clear, X-trace + clear), single-step fanin / fanout via `TraceOverlayController.fromContainer`, save / open session via `SessionController` (per-tab container), exportPng / exportSvg / exportJson via `SchematicExportController.fromContainer` (PNG reads per-tab `schematicCanvasKeyProvider`), importFilelist via `FilelistReader.readAsProject`, all bookmark / annotation / source-pane / diff / FSM / CDC / reset-domain / activity-heatmap / waveform / custom-cell-symbol openers, command palette, close-tab, quit, cross-probe panel, split-pane operations.
- **Setup.** Open a tab with a real Yosys-elaborable design (e.g. the and2 fixture). Open the command palette (Cmd+Shift+P) and exercise every entry. Confirm no entry returns the legacy `"<action> is not yet implemented."` snackbar — that helper has been removed; if you ever see it again, an action was added without a handler.
- **Per-tab-scope guarantee.** Every handler that mutates per-tab state uses `ref.activeTabContainerOrNull(context)` to resolve the active tab's `ProviderContainer` and reads/writes through it. Dispatching from a workspace-screen ref (root scope) into a per-tab provider directly would mutate root-scoped state and miss the actual tab — the canvas would paint blank even though "the action ran." Don't reintroduce that bug.
- **Automation Assessment.** `[Coverage: WIDGET]` for the individual controllers (`session_controller_test`, `schematic_export_controller_test`, `trace_overlay_controller_test`, `filelist_reader_test`). `[Coverage: MANUAL]` for the dispatcher routing — every action's path runs through the same `_dispatchAction` switch, and the enum's exhaustiveness check would surface a missing case at compile time.

### 4.1.10 Keyboard-shortcut conflict resolution & warnings

- **What it does.** Settings → Keyboard Shortcuts lets the user rebind any `NetcruxAction`. When a rebind makes two actions share a chord, NetCrux surfaces the conflict and resolves precedence **deterministically** via `resolveShortcutConflicts` (`lib/core/shortcuts/shortcut_conflicts.dart`), which feeds both the editor warnings and the runtime `ShortcutManagerWidget`.
- **Setup.** Open Settings → Keyboard Shortcuts. Pick two actions with distinct chords (e.g. Zoom In and Zoom Out).
- **Steps.**
  1. Rebind **Zoom In** onto **Zoom Out**'s chord. The binding applies (a warning, not a block).
  2. Verify the warning is **asymmetric**: the remapped row (Zoom In, the customized "interloper") shows an amber **"Takes precedence over Zoom Out"**; the other row (Zoom Out, the default "owner") shows a red **"Won't fire — shadowed by Zoom In"**.
  3. Verify a red **summary banner** ("N shortcut conflict(s) need attention", singular at 1) appears at the top of the section and stays visible when the affected rows are scrolled off-screen; it clears when the conflict is resolved.
  4. Press the contested chord in the app: the **remapped** action (Zoom In) fires — not the default owner. This is the customized-wins rule, independent of `NetcruxAction` declaration order. The shadowed action stays reachable via the command palette / menu bar.
- **Automation Assessment.** `[Coverage: UNIT]` (`test/core/shortcuts/shortcut_conflicts_test.dart` — precedence + count). `[Coverage: WIDGET]` (`test/core/shortcuts/shortcut_manager_widget_test.dart` — runtime precedence; `test/features/settings/widgets/shortcuts_settings_section_test.dart` — asymmetric warning + summary banner). Core resolution algorithm covered cross-suite in `crux_keybindings`.

### 4.1.11 Command palette is always reachable

- **What it does.** The command-palette opener appears in the **View** menu of the desktop menu bar, but **not** inside the command palette's own searchable list (self-referential). Previously it was hidden from every browsable surface, so its keyboard shortcut (Cmd/Ctrl+Shift+P) was the only way in — unbinding it left the palette permanently inaccessible.
- **Steps.**
  1. Open Settings → Keyboard Shortcuts and **unbind** Open Command Palette (backspace icon).
  2. Verify the palette can no longer be opened by Cmd/Ctrl+Shift+P, but **View → Command Palette** still opens it (recovery path — no "reset all" needed).
  3. Open the palette and type "command palette": it does **not** list itself.
- **Automation Assessment.** `[Coverage: UNIT]` (`test/core/shortcuts/netcrux_action_descriptors_test.dart` — the menu surface contains / the palette surface excludes openCommandPalette; grouped under View; the recovery path stays enabled on the empty canvas). `[Coverage: INTEGRATION_TEST]` — `integration_test/command_palette/menu_reachability_test.dart` boots the real app, unbinds `openCommandPalette`'s shortcut via the live `shortcutBindingsProvider`, then dispatches the action through the live `DesktopMenuBar.onAction` callback — the exact call a native View-menu item's `onSelected` makes (`PlatformMenuBar` itself isn't tappable via `WidgetTester`, see the test file's header comment) — and asserts the palette opens and does not list itself.

### 4.1.12 Workspace shell — per-tab IDE layout, chrome-free empty canvas, persisted panels

- **What it does.** NetCrux now mounts its IDE chrome (hierarchy tree left, inspector right, diagnostics drawer bottom) **per-tab**, inside each tab's `ProjectTabContent` via `NetcruxIdeLayout`, rather than as a single outer `IdeLayout` wrapping the whole workspace. This brings NetCrux in line with the WaveCrux / LintCrux / SimCrux workspace-shell model and fixes two defects that fell out of the old outer-chrome model:

  `NetcruxIdeLayout` is a **thin adapter over the shared `crux_ide_layout` package** (`CruxIdeLayout`) — the same widget WaveCrux/SimCrux/LintCrux render. The per-app `IdeController` build/sync boilerplate is gone; NetCrux supplies only `_NetcruxIdePanelLayout` (read: hierarchy→left, inspector→right, diagnostics→bottom; pixel sizes) + `_NetcruxIdePanelLayoutSink` (write: persist visibility/size via `PanelLayoutNotifier`). All user-visible behavior below is unchanged by the lift.
  1. **Chrome-free empty canvas.** On a fresh launch (or after Reset Workspace), `PaneHost` renders the empty-canvas state with **no** side panels and **no** pane separator. Previously the always-mounted left hierarchy panel rendered empty before any design loaded, drawing a stray vertical separator and pushing the "Open Project" actions into a right-hand pane.
  2. **Persisted panel visibility.** Hierarchy / inspector / diagnostics visibility and pane sizes now live in `PanelLayoutState`, are driven by the shared `panelLayoutProvider`, and round-trip to disk via `NetcruxSettingsCodec` under the `netcrux.panelLayout.*` keys. Defaults preserve the historical launch experience: hierarchy **docked**, inspector + diagnostics **collapsed**.
- **Setup.** Fresh build with no existing `workspace.json` and an empty settings store.
- **Steps and expected behavior.**
  1. Launch with zero tabs. Expected: the empty-canvas "Welcome to NetCrux" content fills the full window width — **no** left panel, **no** vertical pane separator, actions centered across the whole canvas (not squeezed into a right pane).
  2. Open a project. Expected: the tab opens with the hierarchy tree docked on the left, inspector + diagnostics collapsed. A pane separator between the hierarchy and the schematic is now expected — this is an *open* tab with chrome.
  3. Toggle the Inspector (View menu / command palette / `Cmd/Ctrl+2`) and the Diagnostics drawer (`Cmd/Ctrl+3`). Expected: each pane shows/hides; the splitter is drag-resizable.
  4. Drag the hierarchy splitter to resize it; toggle the hierarchy off and on.
  5. Quit and relaunch (or open a second window). Expected: the panel visibility + sizes from step 3–4 are restored. Inspect `{appSupportDir}` settings — the `netcrux.panelLayout.inspectorVisible` / `…hierarchyTreeWidth` keys reflect the last state.
  6. Open a second tab and toggle a panel. Expected: panel layout is **shared** across tabs (toggling in one tab moves the same panel in the others) — matching the single-`IdeController` behavior NetCrux had before, and matching LintCrux / SimCrux.
- **Edge cases.** A freshly-opened "+" tab with no source files still shows the IDE chrome (it is an open tab) with the "Open Project" hint in the center — only the **zero-tabs** workspace is chrome-free. Null persisted pane sizes fall back to the `panes` package's own pane-size defaults (the codec removes the key rather than writing a stale pixel value).
- **CXP note.** The CXP outbound emitter (`request`/`NotifySelection` broadcaster) stays mounted at the workspace level, scoped to the **active** tab via `ActiveTabScope`, independent of which panels are open. It is no longer attached to the bottom diagnostics pane (which is now per-tab and collapsible), so hiding the diagnostics drawer no longer stops selection broadcasts. Background tabs do not broadcast.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `PanelLayoutState` equality / copyWith / clear-flags / defaults | `[Coverage: UNIT]` (`test/domain/models/panel_layout_state_test.dart`) |
  | `panelLayoutProvider` toggles + set + persistence + reload-in-fresh-container | `[Coverage: UNIT]` (`test/features/viewer/providers/panel_layout_provider_test.dart`) |
  | `NetcruxIdeLayout` renders + programmatic toggle propagation + seeded state + locale sweep | `[Coverage: WIDGET]` (`test/features/viewer/widgets/netcrux_ide_layout_test.dart`) |
  | `ProjectTabContent` mounts the per-tab `NetcruxIdeLayout` | `[Coverage: WIDGET]` (`test/features/workspace/widgets/project_tab_content_test.dart`) |
  | Panel-layout codec round-trip + null-size key removal | `[Coverage: UNIT]` (`test/services/settings/netcrux_settings_codec_test.dart`) |
  | `AppSettingsNotifier.updatePanelLayout` persistence | `[Coverage: UNIT]` (`test/features/settings/providers/app_settings_provider_test.dart`) |
  | Chrome-free zero-tabs empty canvas (visual — no separator) | `[Coverage: MANUAL]` — the empty-canvas widget test (`empty_canvas_content_test.dart`) asserts the content renders; the *absence of outer chrome* is structurally guaranteed by `PaneHost` returning `emptyCanvasContent` directly when `tabs.isEmpty`, but the "no stray separator on launch" visual is a manual check. |

### 4.1.13 Design status bar — file, top module, cell count

- **What it does.** Each open project tab now pins a thin **status bar** to the bottom of the tab, below the IDE panels (the same design-identity status bar every suite app carries). It shows the loaded design's identity: the primary **source file** (bare filename), the **top module** name, and the **design-wide cell count** (summed across every elaborated module — the flattened total, e.g. ~1 980 for VexRiscv, not just the top scope's direct children). `NetcruxStatusBar` is **app-local** (per-tab, reading this tab's `currentProjectProvider` / `loadedNetlistProvider` directly) — deliberately *not* a shared `crux_workspace` shell, because status-bar content is app-semantic across the suite. Live performance metrics (layout time, FPS, memory) are **not** here — those live in the collapsible live-statistics strip, which docks above this bar.
- **Setup.** A build with Yosys on PATH. Open a real fixture, e.g. `test/fixtures/netlist/vexriscv/captured/vexriscv.v`.
- **Steps and expected behavior.**
  1. Launch with zero tabs. Expected: **no** status bar (the empty canvas is chrome-free; the bar is per-tab).
  2. Open a `+` (empty) tab with no source files yet. Expected: the status bar reads **"No design loaded"**.
  3. Open `vexriscv.v`. Expected, once elaboration completes: the bar reads `File: vexriscv.v · Top: VexRiscv · 1980 cells` (separators are thin vertical dividers; the exact cell count tracks the design).
  4. Open a second design in another tab (e.g. `picorv32.v`). Expected: each tab's status bar reflects **its own** design (the bar is per-tab, not global) — switching tabs swaps the file/module/cell readout.
  5. Narrow the window until the segments would overflow. Expected: the bar scrolls horizontally rather than clipping or wrapping.
- **Edge cases.** A design whose elaboration marks no top module shows the file + cell count and **omits** the "Top:" segment. A project with multiple source files shows the **first** file's basename (the breadcrumb / inspector carry per-file detail). A single-cell design renders the singular **"1 cell"** plural form. A Windows-style source path (`C:\…\foo.v`) still renders the bare `foo.v`.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | Renders file + top module + design-wide cell count from seeded providers | `[Coverage: WIDGET]` (`test/features/viewer/widgets/netcrux_status_bar_test.dart`) |
  | Basename stripping (incl. Windows `\` separator); singular `=1` vs plural `other` cell-count form | `[Coverage: WIDGET]` (same file) |
  | No-design placeholder; file-segment omitted when project has no sources; top-segment omitted when no top module | `[Coverage: WIDGET]` (same file) |
  | Four-locale sweep (en / zh_CN / ja / ko) renders without exceptions | `[Coverage: WIDGET]` (same file) |
  | `ProjectTabContent` mounts the status bar below the IDE layout | `[Coverage: WIDGET]` (`test/features/workspace/widgets/project_tab_content_test.dart`) |
  | Live cell count against a *real* elaborated design (Yosys-dependent end-to-end) | `[Coverage: MANUAL]` — step 3 above; the unit tests seed a synthetic `NetlistModel` rather than run Yosys. |

### 4.1.14 Action toolbar — tier-1 action surface

- **What it does.** A thin **toolbar** spans the full width above the tab strip, completing the three-tier action-discovery model (toolbar + native menu bar + command palette). `NetcruxToolbar` is a "dumb" surface: each button dispatches through the **same** `_dispatchAction` the menu bar and palette use, so action behaviour lives in one place. The curated button set is **open-core only**: Open Project, Open Source Files | Search | Jump to Top, Pop Out Scope, Fit to View. Tooltips reuse each action's localized label (no toolbar-specific ARB keys). Pro features are intentionally **not** on the toolbar (they live in panels / menu / palette with their `FeatureTierBadge`s) — if a Pro action is ever added here it must render a tier badge.
- **Setup.** Any build (no design needed to verify the file-open buttons).
- **Steps and expected behavior.**
  1. Launch with zero tabs. Expected: the toolbar is visible above the empty canvas; **Open Project** / **Open Source Files** work from here (useful before any design is loaded).
  2. Hover each button. Expected: a tooltip shows the action's localized name (the same label the menu bar uses).
  3. Click **Open Source Files**, pick a `.v`. Expected: same behavior as File menu → Open Source Files / the palette entry (one dispatch path).
  4. With a design open, click **Search** (opens the design search dialog), **Jump to Top** (hierarchy → root scope), **Pop Out Scope** (navigate to parent), **Fit to View** (the schematic fits the viewport). Each matches its menu/palette equivalent.
  5. Narrow the window. Expected: the toolbar scrolls horizontally rather than clipping.
- **Edge cases.** On the empty canvas the design-dependent buttons (Search / Jump to Top / Pop Out / Fit) render **greyed out** per the descriptor enablement layer (§4.1.15) and cannot dispatch. Rebinding or removing a keyboard shortcut does not affect the toolbar (the toolbar dispatches the action directly, not via the chord).
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | Renders the curated six-button set | `[Coverage: WIDGET]` (`test/features/viewer/widgets/netcrux_toolbar_test.dart`) |
  | Each button dispatches its matching `NetcruxAction` via `onAction` | `[Coverage: WIDGET]` (same file — taps each icon, asserts the dispatched action) |
  | Every button exposes its action label as a tooltip | `[Coverage: WIDGET]` (same file) |
  | Four-locale sweep (en / zh_CN / ja / ko) renders without exceptions | `[Coverage: WIDGET]` (same file) |
  | Toolbar mounted above the tab strip; workspace body still fills (no Stack-collapse regression) | `[Coverage: WIDGET]` (`test/widget_test.dart`) |
  | Toolbar dispatch reaches the real action behaviour end-to-end (e.g. Open Source Files opens a tab) | `[Coverage: MANUAL]` — steps 3–4; dispatch wiring is unit-covered, the downstream flows have their own entries. |

### 4.1.15 Action enablement layer — descriptor table, greyed states, upgrade dialog

- **What it does.** Every `NetcruxAction`'s surface membership and enabled/disabled state comes from one descriptor table (`descriptorFor` in `lib/core/shortcuts/netcrux_action_descriptors.dart`, ARCHITECTURE §6.5) evaluated over a shared context snapshot (open tab, laid-out design, selection, overlays, analysis results, comparison, waveform, pane count — the per-tab facts mirrored to the root by `activeTabActionFlagsProvider`). Presentation: the **menu bar** greys out disabled items; the **command palette** omits them; the **toolbar** disables their buttons; the **keyboard** refuses to dispatch a disabled action's chord. Tier-gated (PRO/ENT-badged) actions stay enabled and badged regardless of tier; post-beta an insufficient-tier *activation* shows the **upgrade-required dialog** (`NetcruxUpgradeDialog` — tier badge, the activated feature's name, the required product tier) instead of silently doing nothing.
- **Setup.** Any build. For the enablement walk, start with zero tabs; for the tier scenarios, a Pro-tier action (e.g. Run CDC Analysis) and control over the beta flag.
- **Steps and expected behavior.**
  1. **Empty-canvas walk.** With zero tabs, open the File / View / Navigate / Tools menus. Expected: Open Project / Open Source Files / Import Filelist / Settings / About / Quit / Symbol Manager / Import Symbol / Cross-Probe Panel / Command Palette are enabled; everything design- or tab-dependent (zoom, fit, exports, sessions, close project, pane management, every analysis run/pane, every clear action) is greyed out. The toolbar's Search / Jump to Top / Pop Out / Fit buttons are disabled; Open Project / Open Source Files stay live.
  2. **Palette omission.** Open the palette with zero tabs. Expected: only the enabled subset is listed (no greyed rows); typing "Zoom" finds nothing.
  3. **Keyboard inertness.** With zero tabs press a design-gated chord (e.g. `[` fanin). Expected: nothing happens — the chord is inert, not a hidden no-op.
  4. **Progressive enablement.** Open a design: zoom / fit / exports / search / session save / analysis runs enable. Select a cell: fanin/fanout, cone-of-influence, add bookmark/annotation, per-selection analysis scoping enable. Run a CDC analysis: Clear CDC Analysis Selection enables. Load a comparison netlist: next/prev divergence + clear comparison enable.
  5. **Tier gate — beta (`kBetaPeriod = true`, shipping default).** Activate any PRO-badged action at any tier. Expected: it activates normally; the upgrade dialog never appears (the badge is communication, not enforcement).
  6. **Tier gate — post-beta (`kBetaPeriod = false`).** At open-core tier, activate a PRO-badged action from the menu or palette. Expected: the action stays enabled + badged; activation shows the upgrade dialog naming the feature and "NetCrux Pro"; OK dismisses; nothing else happens. With a Pro/EDU license the same activation proceeds normally.
- **Edge cases.** Split the workspace: Split Pane Right greys out (already split) while Close Pane / Focus Other Pane / Move Tab enable. `showXTrace` / `showXTracePanel` appear on **no** surface until the X-trace result panel ships (their descriptors declare no surfaces); Clear X-Trace stays discoverable and enables only with a result present. The cross-probe panel stays enabled at zero peers — it is the surface that explains peer status.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | Descriptor table invariants (surfaces, empty-canvas walk, selection-seeded gating, migrated hidden-set pins) | `[Coverage: UNIT]` (`test/core/shortcuts/netcrux_action_descriptors_test.dart`) |
  | Menu / palette / toolbar render exactly the table's presence + enablement across a five-context matrix | `[Coverage: WIDGET]` (`test/core/shortcuts/action_surface_conformance_test.dart`) |
  | Keyboard chord of a disabled action does not dispatch; enabled chord does; production resolver wiring | `[Coverage: WIDGET]` (`test/core/shortcuts/shortcut_manager_widget_test.dart`, `test/features/workspace/screens/workspace_screen_gating_test.dart`) |
  | Root mirror tracks the active tab + rebinds on tab switch (two-tab isolation) | `[Coverage: UNIT]` (`test/features/workspace/providers/active_tab_action_flags_provider_test.dart`) |
  | Upgrade dialog on post-beta denial; never during beta; both dispatch-gate ways | `[Coverage: WIDGET]` (`test/features/workspace/services/workspace_action_dispatcher_test.dart`, `workspace_screen_gating_test.dart`) |
  | Upgrade dialog rendering + dismissal, 4-locale sweep | `[Coverage: WIDGET]` (`test/shared/widgets/netcrux_upgrade_dialog_test.dart`) |
  | Live end-to-end enablement walk with a real design | `[Coverage: MANUAL]` — steps 1–4. |

### 4.1.16 Tab identity — a CLI open of an already-open design focuses it

- **What it does.** Opening a design NetCrux already has open — from the command line, the file picker, a recent-files entry, or a filelist import — activates the existing tab instead of appending a second copy of it. Identity is computed by `NetcruxWorkspaceCodec.identityOf` and consumed by `crux_workspace`'s `WorkspaceNotifier.openTab(dedupe:)`. Before this, a project passed on the command line at every launch accumulated one tab per launch, without bound, because the restored tab and the CLI tab were never compared.
  Identity is a **canonical path key** (`canonicalPathKey` from `package:crux_io`): absolute, `..`-collapsed, trailing-separator-stripped, symlink-resolved, and case-folded on macOS/Windows. A project tab is keyed on its `.netcrux-project` path; a source-file tab is keyed on the **set** of its source paths, order-independent. Deliberately *not* deduped: a project tab against a source-file tab naming the same file (different views of the design), an overlapping-but-unequal source set (a different design), and blank "+" tabs (no path, so no identity — the second blank tab stays openable).
- **Setup.** A `.netcrux-project` on disk, plus two loose HDL sources. A terminal, so the same path can be handed over in several spellings.
- **Steps and expected behavior.**
  1. Launch NetCrux with the project path: `netcrux /abs/path/demo.netcrux-project`. Expected: one tab.
  2. Quit and relaunch with the **same** command. Expected: still **one** tab — restored, focused, not duplicated.
  3. Relaunch from the project's own directory with a relative path (`netcrux ./demo.netcrux-project`), then with a trailing separator, then via `sub/../demo.netcrux-project`, then (macOS/Windows) with the file name's case changed. Expected: one tab each time.
  4. With the project tab open, use Open Project… and pick the same file. Expected: no new tab; the existing tab takes focus (and its pane becomes the active pane if it was in the other one).
  5. Open two loose sources as one tab (`netcrux a.v b.v` opens one tab per file, so instead use Open Source Files… and multi-select both). Relaunch and re-open the same two files with the picker's selection order reversed. Expected: one tab.
  6. Open the same two sources **plus** a third. Expected: a **new** tab — a different source set is a different design.
  7. With the project tab open, open one of the project's own source files directly via Open Source Files…. Expected: a **new** tab. These are two different views and are not merged.
  8. Press "+" twice on the tab bar. Expected: two blank tabs.
- **Diagnostics-assisted verification.** `{appSupportDir}/workspace.json` holds exactly one `tabs` entry per distinct design after any number of relaunches. If a duplicate does appear, compare the two entries' `projectFilePath` / `sourceFiles` strings — they will differ in spelling, and that spelling is the missing canonicalization case.
- **Edge cases.** A payload whose path no longer exists on disk still dedupes: `canonicalizePath` fails soft and falls back to the absolute-normalized form, so a tab whose design was deleted still compares equal to itself. Symlink resolution is best-effort for the same reason. Case folding is a platform heuristic — a case-*sensitive* macOS volume would merge two genuinely distinct files; the trade is documented on `filesystemIsCaseInsensitive` in `crux_io`.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `identityOf` across relative / trailing-separator / `..` / symlink / case spellings; project-vs-source namespaces; set order and set inequality; view state excluded | `[Coverage: UNIT]` (`test/services/workspace/netcrux_workspace_identity_test.dart`) |
  | `openTab` focuses the existing tab, `dedupe: false` still opens a second view, two blank tabs stay independent | `[Coverage: UNIT]` (same file) |
  | Dedupe against a tab **rehydrated from disk** — the actual bug shape, which a same-session-only test would pass without canonicalization | `[Coverage: UNIT]` (same file, `a CLI open dedupes against a tab rehydrated from disk`) |
  | The live launch path (real CLI argument → real `WorkspaceScreen` auto-launch handler → one tab) | `[Coverage: INTEGRATION_TEST — pending]` — run steps 1–4 manually until it lands |
  | Picker / recent-files / filelist re-open focusing the existing tab | `[Coverage: MANUAL]` — steps 4–7 |

### 4.1.17 Restore tabs on launch — the preference, and where the state actually lives

- **What it does.** Settings → General → **Restore tabs on launch** (default **on**) decides whether the persisted workspace document is rehydrated at launch. `NetcruxWorkspaceNotifier.shouldRestoreOnLaunch` is consulted **before** `WorkspaceService.load` runs, so declining never pays for the load and never emits a scope reconcile for tabs it is about to discard. Declining **leaves `workspace.json` on disk untouched** — the file is only overwritten once the user mutates the fresh workspace — so turning the preference back on brings the previous session back. The preference had been persisted (as the suite-shared `settings.restoreTabsOnLaunch` key) since the workspace landed, but nothing read it and no product surfaced it, so the only way to set it was `defaults write`.
- **Where NetCrux's workspace state lives.** Deleting the wrong file is the standard way to conclude that a preference "does not work", so:

  | Path | Owner | Contents |
  |---|---|---|
  | `{appSupportDir}/workspace.json` | `crux_workspace`'s `WorkspaceService` | The open tabs and panes — **this is the one that matters** |
  | `{appSupportDir}/workspace.json.corrupt-<timestamp>` | same | Quarantined copy of an unreadable document |
  | `{appSupportDir}/workspace.json.<n>.tmp` | same | Transient atomic-write sibling; swept by `clear()` |
  | The `SharedPreferences` store | `crux_settings` | `settings.restoreTabsOnLaunch` and every other setting |

  `{appSupportDir}` is `~/Library/Containers/com.ferriteengineering.netcrux/Data/Library/Application Support/com.ferriteengineering.netcrux/` on sandboxed macOS (`…netcruxPro…` for the Pro build), `~/.local/share/com.ferriteengineering.netcrux/` on Linux, and `%APPDATA%\com.ferriteengineering\netcrux\` on Windows. The `SharedPreferences` store is `~/Library/Preferences/com.ferriteengineering.netcrux.plist` on macOS (readable with `defaults read com.ferriteengineering.netcrux`), and prefixes every key with `flutter.` — the preference is therefore `flutter.settings.restoreTabsOnLaunch`.

  Two things NetCrux **does not** have, which sibling products do: there is no second `{appSupportDir}/<product>/workspace.json` (NetCrux does not consume `crux_projects`, so nothing re-seeds the tab document from a project registry) and no `{appSupportDir}/sessions/<tabId>.<ext>` sidecars. Deleting `{appSupportDir}/workspace.json` is sufficient to reset a NetCrux session.
- **Setup.** A build with at least two tabs open and quit cleanly, so a populated `workspace.json` exists.
- **Steps and expected behavior.**
  1. Open Settings → General. Expected: a **Restore tabs on launch** row, on, above **Automatically check for updates**.
  2. Turn it off. Expected: the toggle flips immediately; `defaults read com.ferriteengineering.netcrux flutter.settings.restoreTabsOnLaunch` reads `0`; `workspace.json` is unchanged on disk.
  3. Quit and relaunch. Expected: the empty-canvas state — **no** restored tabs. `workspace.json` is still on disk with both tabs in it.
  4. Open Settings → General and turn it back on, quit, relaunch. Expected: both tabs come back exactly as they were.
  5. Repeat step 3, then open a project before quitting. Expected: the fresh session's single tab is what relaunch #2 would restore — the old document was overwritten only once the workspace was mutated.
  6. **Restore on + CLI argument.** With restore on and a two-tab session saved, relaunch with one of those two projects on the command line. Expected: exactly two tabs — both restored, the CLI one focused, nothing appended. Repeat five times: still two tabs.
  7. Set the preference from outside the app (`defaults write com.ferriteengineering.netcrux flutter.settings.restoreTabsOnLaunch -bool false`) and relaunch. Expected: same as step 3 — the UI and `defaults` write the same key.
- **Diagnostics-assisted verification.** After a declined restore, `workspace.json`'s modification time must be unchanged until the first workspace mutation.
- **Edge cases.** An unreadable preferences store defaults to **restoring** — losing a session because a *preference* could not be read is the worse failure. The gate reads the settings **service** (a plain future), never `appSettingsProvider.future`: awaiting a second async provider there hands the launch path to Riverpod's failure retry, and a settings load that throws then leaves the workspace future pending across every retry, so the app never renders. That trap is recorded on the seam's doc comment in `crux_workspace`.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | Gate honours the persisted preference both ways; declining leaves the document byte-identical on disk and a later "on" restores it | `[Coverage: UNIT]` (`test/services/workspace/netcrux_workspace_restore_gate_test.dart`) |
  | An unreadable settings store defaults to restoring **and the workspace future still completes** (the deadlock guard) | `[Coverage: UNIT]` (same file) |
  | Settings → General row: default on, reflects a persisted off, writes through to the suite-shared key, 44 dp touch target, 4-locale sweep | `[Coverage: WIDGET]` (`test/features/settings/screens/settings_restore_tabs_tile_test.dart`) |
  | `settings.restoreTabsOnLaunch` survives a `NetcruxSettingsCodec` round-trip and defaults to on | `[Coverage: UNIT]` (`test/services/settings/netcrux_settings_codec_test.dart`) |
  | Real quit/relaunch with the preference off | `[Coverage: MANUAL]` — steps 3–7 (the framework forbids a second `runApp` per process, so a literal relaunch cannot be automated in-process) |

### 4.1.18 Command palette — Enter executes the highlighted action

- **What it does.** With the palette open and a row highlighted, Enter runs that action and closes the palette; ↑/↓ move the highlight without moving the query field's caret; Escape closes without dispatching. This was dead in shipped desktop builds — only a pointer click executed — which removed the palette's keyboard flow entirely, and with it the only surface for several pane actions (Move Tab to Other Pane).
  The cause was in the shared `crux_command_palette` package, not in NetCrux: on every platform whose engine owns the focused field's text-input connection, Enter is translated into a `TextInputAction.done` on the **text-input channel** and the framework never sees a key event, so an ancestor key listener alone can never see it. NetCrux inherits the fix through the `crux-shared` pin; `CommandPaletteDialog` is a delegating wrapper and needed no change.
- **Setup.** Any build, any tab state.
- **Steps and expected behavior.**
  1. Cmd/Ctrl+Shift+P, type `split pane`. Expected: **Split Pane Right** highlighted.
  2. Press Enter. Expected: the palette closes and the pane splits. (Before the fix: the palette stayed open and nothing happened.)
  3. Repeat with `move tab`. Expected: the tab moves to the other pane.
  4. Open the palette, type a query with several matches, press ↓ twice. Expected: the highlight moves two rows; the text caret stays where it was and the query text is unchanged.
  5. Press Escape. Expected: the palette closes; **only** the palette closes — the window underneath is untouched.
- **Edge cases.** A platform that delivers *both* an Enter key event and a done action must dispatch once and pop once; a double pop would take the route underneath the palette with it. An empty result list swallows Enter (nothing to run) and leaves the palette open.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | Enter delivered as a **text-input done action** executes the highlighted row (the delivery path a real keypress takes; `tester.sendKeyEvent` cannot reproduce it, which is why the defect shipped past a green suite) | `[Coverage: WIDGET]` (`test/features/command_palette/widgets/command_palette_enter_test.dart`) |
  | Enter delivered as a framework key event executes it too; both signals together dispatch exactly once and pop exactly once | `[Coverage: WIDGET]` (same file) |
  | ↑/↓ move the highlight without the field absorbing them; Escape closes without dispatching | `[Coverage: WIDGET]` (same file) |
  | 4-locale sweep of the Enter path | `[Coverage: WIDGET]` (same file) |
  | Live keyboard-only palette drive in a release build | `[Coverage: MANUAL]` — steps 1–5 |

### 4.1.19 Shipped `examples/` open from a clean checkout

- **What it does.** [`examples/`](../examples/README.md) holds two committed `.netcrux-project` files a first-run user can open without hunting through `test/fixtures/` — `adder4` (five ports, two `$add` cells; the "does my Yosys work" smoke test) and `cdc-capture` (the suite's shared two-clock-domain demo design; 18 cells, 7 `$adff` flops). Both reference RTL under `test/fixtures/verilog/` with paths **relative to the project file**, which is what makes them portable across checkouts.
  Two defects had to be fixed for a committed project to work at all, and both are what this section actually guards. (1) `.netcrux-project` source paths were never anchored to the project file's directory — they reached Yosys verbatim and were resolved against the *process* working directory, which for a Finder/launcher launch is unrelated to the project, so any relative path failed with "No such file" naming a path the user can see is present. `resolveProjectPaths` now anchors them. (2) Opening a project discarded its `defines`, `includePaths`, `extraYosysCommands` and per-file language overrides — only `sourceFiles` and `topModule` survived into the tab. The resolved project is now pushed whole.
- **Setup.** A clean checkout and `yosys` on `PATH`. Deliberately verify from a working directory that is **not** the repo root (e.g. `cd /` first, or launch from Finder) — the anchoring bug is invisible when the CWD happens to be the repo root.
- **Steps and expected behavior.**
  1. **File → Open Project…** (`Cmd/Ctrl+O`), pick `examples/adder4/adder4.netcrux-project`. Expected: a tab named `adder4` opens and a schematic with ports `a`, `b`, `cin`, `sum`, `cout` renders. No "No such file" diagnostic.
  2. Repeat for `examples/cdc-capture/cdc-capture.netcrux-project`. Expected: a schematic with the flops and muxes of both clock domains; the Hierarchy dock (left) lists `cdc_capture`; the status bar reports the top module and a non-zero cell count.
  3. Select the `req_a` net, then **Navigate → Show Fanin** (`[`). Expected: the overlay dims everything that is not a driver; **Navigate → Clear Selection / Overlay** (`Esc`) restores.
  4. **Search → Search…** (`Cmd/Ctrl+F`), query `req`. Expected: matches for the request pulse and the flops sampling it.
  5. From a terminal in an unrelated directory: `netcrux /abs/path/examples/adder4/adder4.netcrux-project`. Expected: opens as a **project** tab, not as an HDL source. (Before the extension fix, `p.extension` returned `.netcrux-project`, missed the `.netcrux` equality test, and routed the JSON to Yosys as if it were Verilog.)
- **Edge cases.** With Yosys absent the examples must **degrade, not look broken**: the tab still opens and the canvas shows "Elaboration failed" over "Yosys was not found on your PATH. Install Yosys, or set a custom path in Settings.", with the persistent `Yosys not found` status-bar segment. An example that names a source nobody committed, or a `topModule` no source declares, must fail the guard suite rather than reach a user.
- **Known limitation — no toolchain-free example.** Unlike SimCrux (replayed logs) and LintCrux (a captured SARIF report), NetCrux has no entry point that works with nothing installed: the `.netcrux-project` schema has no netlist field, the elaboration cache is in-memory only, and every desktop route to a `NetlistModel` passes through a live Yosys subprocess. A mixed-language (VHDL) example is likewise **not** shippable today — `vhdlTopUnit` is derived from `topModule`, so GHDL is asked to elaborate the Verilog top as a VHDL entity and fails before Yosys runs; the guard suite asserts no shipped example contains VHDL so this cannot be reintroduced by accident.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | Every example decodes through the real `NetcruxProjectFileReader`, anchors through the real `resolveProjectPaths`, and each declared source resolves to a committed file | `[Coverage: UNIT]` (`test/examples/examples_test.dart`) |
  | Each example's `topModule` is actually declared in one of its sources | `[Coverage: UNIT]` (same file) |
  | The real `LoadedNetlist.buildRequest` names every source in the right language, and no example ships VHDL | `[Coverage: UNIT]` (same file) |
  | Anchoring: relative → project-dir, absolute untouched, `..` collapsed, language-override keys rewritten in step, elaboration knobs preserved, idempotent | `[Coverage: UNIT]` (`test/services/project/netcrux_project_path_resolver_test.dart`) |
  | A positional `.netcrux-project` CLI arg routes to `openProject` | `[Coverage: UNIT]` (`test/core/cli/cli_arg_parser_test.dart`) |
  | Real elaboration of both examples through a real Yosys, from a non-repo working directory | `[Coverage: MANUAL]` — steps 1–5 |
  | Yosys-absent degradation wording | `[Coverage: MANUAL]` — edge cases |

## 4.2 Seeded-design journey — load → navigate hierarchy → select → inspect

- **What it does.** Proves the core viewer loop against a *loaded* design without requiring Yosys on the test host: a committed hierarchical netlist-JSON fixture is parsed through the real `YosysJsonParser` and injected into the active tab's per-tab `loadedNetlistProvider`; the user-visible journey is then driven through the real UI — hierarchy tree renders the design, tapping a scope row navigates the schematic into that scope, selecting a cell populates the Inspector with instance / type / kind / ports.
- **Setup.** None beyond the repo: the design-seed harness lives in `integration_test/helpers/app_driver.dart` (`designSeedBootOverrides()` + `seedDesignIntoNewTab()`), and the fixture is `integration_test/fixtures/design_seed_netlist.dart` — a generated Dart-const mirror of `test/fixtures/netlist/design_seed/generated/design_seed.netlist.json` (regenerate both with `dart run tool/generate_design_seed_fixture.dart`; a sync test pins them together). The fixture is a 3-level hierarchy `top` → `u_cpu` (`cpu`) → `u_alu` (`alu`) with primitive siblings at each level.
- **Steps and expected behavior.**
  1. Boot with `designSeedBootOverrides()` (pins the Yosys probe to unavailable — the pipeline settles deterministically and never spawns a subprocess) and seed the fixture. Expected: hierarchy panel shows root `top`; the top scope lays out with cells `u_cpu` and `dma_reg`; the schematic center is mounted (non-empty project).
  2. Programmatically select cell `u_cpu`. Expected: Inspector renders the cell card — instance `u_cpu`, type `cpu`, plus the per-port direction table.
  3. Tap the `u_cpu` hierarchy row. Expected: the selected scope becomes `u_cpu`; the canvas re-lays-out to the `cpu` module (cells `u_alu`, `pc_reg`).
  4. Select cell `u_alu`. Expected: Inspector shows instance `u_alu`, type `alu`.
- **Diagnostics-assisted verification.** Not applicable — the journey asserts through providers and rendered widgets directly.
- **Edge cases / break-it tests.** The harness itself guards its two failure modes: booting without `designSeedBootOverrides()` throws (a live Yosys elaboration could race the injected model), and the injected model is stable because the elaboration providers no longer auto-retry — `loadedNetlistProvider` / `currentLaidOutGraphProvider` opt out of Riverpod's exponential-backoff retry (`noElaborationRetry`), since elaboration failures are deterministic and each retry re-spawned Yosys and churned every listener (this was a live product defect, not just a test problem; the error view's Retry button still re-runs explicitly).
- **Automation Assessment.** `[Coverage: INTEGRATION_TEST]` — `integration_test/design/seeded_design_journey_test.dart` (macOS). Fixture-shape guardrails: `[Coverage: UNIT]` — `test/fixtures/design_seed_fixture_sync_test.dart` (Dart-const ↔ JSON sync + 3-level hierarchy parse) and the parser golden sweep (`test/services/yosys/netlist_golden_test.dart`, design `design_seed`). Real-Yosys elaboration end-to-end remains `[Coverage: MANUAL]` per §4.1.13.

---

## 4.3 Elaboration cache — re-open the same design without re-running Yosys

- **What it does.** An in-memory LRU (`ElaborationCacheService`, root-scoped) keyed on each source file's path + size + mtime plus the Yosys version and the full request options (top module, defines, include paths, extra commands). A re-elaboration with unchanged inputs returns the previously **parsed** `NetlistModel` and that run's stderr instantly — no Yosys spawn, no re-parse (the sub-50 ms cache-hit round-trip budget). Bounded by entry count (32) and total bytes (256 MB of raw-JSON-length proxy); the newest entry is exempt from eviction since its model is alive in the provider anyway.
- **Setup.** Any host with Yosys on PATH and a small Verilog project.
- **Steps and expected behavior.**
  1. Open a project; note the elaboration duration in the status strip.
  2. Close the tab and re-open the same project (or trigger a re-elaboration without touching the sources). Expected: the schematic appears near-instantly; the Tab Diagnostics drawer shows the SAME Yosys warnings as the first run (stderr is cached alongside the model).
  3. Touch a source file and re-open. Expected: a real re-elaboration (the fingerprint changed).
  4. Change the Yosys binary (Settings → Engines). Expected: a real re-elaboration (the version is in the key).
- **Edge cases.** Editing only an `include`d header does not change the key (the include dirs are fingerprinted, their contents are not) — the same accepted blind spot as the per-tab source watcher; a manual re-open after touching the top-level sources always misses. Cancelled or failed runs are never cached; a parse failure is not cached either.
- **Automation Assessment.** `[Coverage: UNIT]` — `test/services/yosys/elaboration_cache_service_test.dart` (LRU + byte-budget + fingerprint semantics, including the version-only miss) and `test/features/project/providers/loaded_netlist_provider_test.dart` (pipeline-level: unchanged inputs are served from the cache with the same model instance and restored stderr; a touched source misses and re-spawns). The <50 ms wall-clock budget itself is `[Coverage: MANUAL]`: wall-clock budgets are soft and are not asserted on shared runners.

---

## 4.4 Schematic canvas navigation — push-in / pop-out, breadcrumb, LOD, pan/zoom

- **What it does.** The core "walk the design" loop. `SchematicGraphBuilder` turns the current scope into a layout-ready `SchematicGraph` (paired with the `CellKind` taxonomy); `SchematicPainter` is a direct-paint `RenderBox` honoring selection + trace-overlay state; `SchematicGestureHandler` handles Cmd/Ctrl+wheel zoom, trackpad/middle-button pan, arrow-key pan, `+`/`-` zoom, `0` fit-all, clamped to 10%–1000%. Double-click on an instance pushes in; double-click on empty canvas / Backspace / Cmd+[ pops out; `BreadcrumbBar` renders `top.cpu.alu` with clickable segments. `LodBandRouter.bandFor(zoom)` selects one of three LOD bands per frame (detail ≥0.75 = symbols + labels; mid 0.25–0.75 = drop labels; overview <0.25 = family-colored rectangles). The cell-symbol library (AND/OR/NOT/MUX/FF/latch/generic box) is golden-pinned per `CellKind`.
- **Setup.** A loaded design — either the seeded-design harness (§4.2) or a real fixture with Yosys on PATH (e.g. `test/fixtures/verilog/fsm.v`).
- **Steps and expected behavior.**
  1. Cmd/Ctrl+scroll to zoom. Expected: zoom clamps at 10% / 1000%; the LOD collapses labels then cells as you zoom out.
  2. Double-click an instance cell. Expected: the canvas pushes into that scope; the breadcrumb appends the segment.
  3. Backspace (or double-click empty canvas, or Cmd+[). Expected: pop out one level; breadcrumb drops the last segment.
  4. Click a breadcrumb segment. Expected: jump directly to that ancestor scope.
  5. Press `0`. Expected: the whole schematic fits the viewport (centered, not cornered).
  6. **Zoom In on every layout.** On a US layout press Cmd/Ctrl+`=`, then Cmd/Ctrl+Shift+`=` (Cmd/Ctrl+`+`), then Cmd/Ctrl+numpad `+`. Expected: each zooms in one step. Switch the OS keyboard layout to Swedish or German and press Cmd/Ctrl+`+` (the key right of `0`). Expected: zoom in. Cmd/Ctrl+numpad `-` zooms out and Cmd/Ctrl+numpad `0` fits. The View menu still shows Cmd/Ctrl+`=` beside Zoom In. Rebind Zoom In in Settings > Keyboard Shortcuts to another chord: Cmd/Ctrl+`+` no longer zooms, the new chord does; reset the binding and Cmd/Ctrl+`+` works again.
  7. **Focus follows the pointer onto the canvas.** Click a row in the Hierarchy tree (focus is now in the tree), move the pointer onto the schematic without clicking, press `=` and `-`. Expected: the canvas zooms in and out; `0` fits. Click into the Hierarchy filter field, type a few characters, move the pointer across the schematic and keep typing. Expected: the text keeps going into the filter, `=` typed there appears in the field and does not zoom. Right-click empty canvas (or middle-drag), then press `=`. Expected: the canvas has focus and zooms, even when the filter field had focus before.
- **Edge cases.** An empty / missing scope produces an empty graph, not a crash. Very small zoom (sub-0.1) is clamped and still renders the overview band. High-fanout nets are elided by the layout policy. With two panes split, moving the pointer from one canvas onto the other moves keyboard focus with it, so the bare zoom keys act on the canvas under the pointer. An open in-window menu (Windows / Linux) keeps keyboard focus while the pointer crosses the canvas.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `SchematicGraphBuilder` builds correct graphs for and2 / adder4 / fsm + empty/missing scope | `[Coverage: UNIT]` (`test/services/schematic/schematic_graph_builder_test.dart`) |
  | `SchematicPainter` paint + selection/overlay honoring; LOD threshold golden | `[Coverage: UNIT]` (`test/features/viewer/rendering/schematic_painter_test.dart`) + `[Coverage: UNIT]` (`schematic_painter_golden_test.dart`) |
  | `LodBandRouter.bandFor` band boundaries | `[Coverage: UNIT]` (`test/features/viewer/rendering/lod_band_test.dart`) |
  | Gesture handler: scroll-wheel zoom, auto-fit, keyboard pan/zoom, middle-button drag | `[Coverage: WIDGET]` (`test/features/viewer/widgets/schematic_gesture_handler_test.dart`) |
  | `ViewportTransformNotifier` pan / setZoom / zoomAt / reset / fitToBounds (incl. sub-0.1) | `[Coverage: UNIT]` (`test/features/viewer/providers/viewport_transform_notifier_test.dart`) |
  | `BreadcrumbBar` renders clickable segments + locale sweep | `[Coverage: WIDGET]` (`test/features/viewer/widgets/breadcrumb_bar_test.dart`) |
  | Cell-symbol library per `CellKind` | `[Coverage: UNIT]` (`test/features/viewer/symbols/symbol_painters_test.dart`) |
  | Hierarchy push-in / pop-out state transitions | `[Coverage: UNIT]` (`test/features/hierarchy/providers/hierarchy_tree_notifier_test.dart`, selectScope/expand paths) |
  | Double-click push-in / empty-canvas pop-out *gesture* on a live canvas | `[Coverage: MANUAL]` — steps 2–3; the notifier transitions are unit-covered, the pointer gesture is not. |
  | Zoom In on Cmd/Ctrl+`=`, Cmd/Ctrl+`+` (with and without Shift) and Cmd/Ctrl+numpad `+`; numpad `-` / `0` with the modifier; the aliases follow the default binding and never take another action's chord (step 6) | `[Coverage: UNIT]` (`test/core/shortcuts/shortcut_bindings_test.dart`) + `[Coverage: WIDGET]` (`test/core/shortcuts/shortcut_manager_widget_test.dart`, "zoom aliases and Zoom to Selection" group, which simulates the Swedish / German `+` key) + `[Coverage: MANUAL]` (a real Swedish or German OS layout) |
  | Pointer entering the canvas takes focus from a panel so bare `=` zooms; a text field mid-edit keeps focus; a right-click takes focus even from a text field (step 7) | `[Coverage: WIDGET]` (`test/features/viewer/widgets/schematic_gesture_handler_test.dart`, "focus follows the pointer" group) + `[Coverage: MANUAL]` (step 7 on a real window, split panes, an open in-window menu) |

---

## 4.5 Selection & inspector — hit-testing, sealed selection, inspector panel

- **What it does.** Clicking an element selects it and populates the right-pane inspector. `SelectedElementNotifier` holds a sealed `SelectedElement` (none / cell / port / boundaryPort / wire); `SchematicHitTester` resolves a pointer to an element in the order port → cell → boundary → wire (with touch-slop on wires); `InspectorPanel` renders the type / instance / parameters / port-bindings for the selection. The `Selection` model additionally supports multi-select (plain click = single, Shift = additive, Cmd/Ctrl = toggle, Esc = clear) with a `primary` anchor, and the canonical hierarchical path helper backs Copy-Path / cross-probe.
- **Setup.** A loaded design (§4.2 harness or a real fixture).
- **Steps and expected behavior.**
  1. Click a cell. Expected: it highlights; the inspector shows instance + type + kind + per-port direction table.
  2. Click a port, then a wire. Expected: the inspector swaps to the port / wire surface; hit priority resolves a port over the cell under it.
  3. Shift-click a second cell, then Cmd/Ctrl-click one to toggle it off. Expected: additive / toggle multi-select; `primary` tracks the anchor.
  4. Press Esc / click empty canvas. Expected: selection clears; inspector shows the none surface.
  5. **Click latency.** Every click above must take effect the instant the mouse button is *released* — no perceptible pause between the click and the highlight / inspector update. Click a cell, then immediately click a different cell: both register, and the second is not swallowed. (Before the 2026-07 fix, selection hung off `GestureDetector.onTapUp`, which cannot fire until the tap recognizer wins the gesture arena — and the double-click-to-push-in recognizer holds that arena open for the whole `kDoubleTapTimeout`, ~300 ms. The canvas felt unresponsive and a quick second click was eaten as a double-click. Selection now runs off the raw pointer stream, outside the arena.)
  6. **Drag-to-cancel.** Press the left button on a cell, drag more than ~20 px, release. Expected: the canvas **pans** and the selection is **unchanged** — selection fires on release-without-drag, never on press, precisely so a pan that starts on top of an element does not select it.
  7. **Double-click still works.** Double-click a cell: it pushes into that scope (breadcrumb advances) and the selection clears behind the scope change. Double-click empty canvas: pops out.
  8. **Keyboard reach.** With the canvas focused and no mouse: Alt+Down / Alt+Up select the cells and module ports top to bottom then left to right; Alt+Right / Alt+Left step through the pins of the cell the walk is on, each followed by the net on it (a module port: its net), and the inspector follows each pin and net; Shift with either adds to the selection; Enter pushes into a selected instance; Shift+F10 or the Menu key opens the same context menu a right-click does, anchored on the element, and Esc returns focus to the canvas. With NVDA or VoiceOver running, each step is spoken ("u_alu, $alu cell", "Pin A of u_alu", "Net data_out", "Port clk"); with nothing selected the menu key says "Nothing is selected". In a Pro build the menu's cross-probe entries dispatch to a connected peer exactly as from a right-click.
  9. **Hierarchy tree from the keyboard.** Tab into the Hierarchy: focus lands on one row — the selected scope, ringed — and a second Tab leaves the tree. Up / Down move between rows, Home / End to the ends; Right expands a collapsed row and, pressed again, moves to its first child; Left collapses an expanded row and, on a collapsed or leaf row, moves to its parent; Enter or Space selects the scope and the canvas follows. Move far down a long tree with End: the row scrolls into view with focus on it. The expand arrows still respond to the mouse but are never a Tab stop. A screen reader reads each row as "u_cpu (cpu), 3 cells, button, collapsed" and adds "selected" on the current scope.
- **Edge cases.** A wire hit only registers within the touch-slop band. Selecting nothing renders the "no selection" inspector state, not an empty panel. A trackpad pinch (two pointers) never leaves a stray selection behind when the fingers lift.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `SelectedElementNotifier` select / clear / per-tab isolation | `[Coverage: UNIT]` (`test/features/viewer/providers/selected_element_notifier_test.dart`) |
  | Sealed `SelectedElement` variants + `Selection` multi-select model | `[Coverage: UNIT]` (`test/features/viewer/selection/selected_element_test.dart`, `selection_test.dart`) |
  | `SchematicHitTester` order (port→cell→boundary→wire) + wire slop | `[Coverage: UNIT]` (`test/features/viewer/selection/schematic_hit_test_test.dart`) |
  | Canonical element-path helper | `[Coverage: UNIT]` (`test/features/viewer/selection/element_path_test.dart`) |
  | `InspectorPanel` renders cell / port / wire / none surfaces | `[Coverage: WIDGET]` (`test/features/inspector/widgets/inspector_panel_test.dart`) |
  | End-to-end select-cell → inspector-populates on a driven canvas | `[Coverage: INTEGRATION_TEST]` (`integration_test/design/seeded_design_journey_test.dart`, §4.2) |
  | Click selects the hit cell on the **first frame** after the click, with no clock advance (plain, empty-canvas-clears, shift-additive) | `[Coverage: WIDGET]` (`test/features/viewer/widgets/schematic_gesture_handler_test.dart` — "click selection" group). Asserting after a `pump(300 ms)` would hide the arena defect entirely; these cases were verified to fail against the pre-fix handler. |
  | Drag past the tap slop pans without selecting (drag-to-cancel) | `[Coverage: WIDGET]` (same group — "a drag past the tap slop pans without selecting") |
  | Keyboard selection order: cells and ports in reading order; each pin followed by its net, a shared net once; pin / wire anchoring | `[Coverage: UNIT]` (`test/features/viewer/selection/schematic_keyboard_navigator_test.dart`) |
  | Alt+Arrow selection and its announcements, Shift to add, Enter push-in, Shift+F10 / Menu key opens the element menu and returns focus (step 8) | `[Coverage: WIDGET]` (`test/features/viewer/widgets/schematic_gesture_handler_keyboard_reach_test.dart`) + `[Coverage: MANUAL]` (the spoken result with a real screen reader; Pro cross-probe dispatch from the keyboard-opened menu) |
  | Hierarchy tree is one Tab stop; Up/Down/Home/End, Right expand-then-enter, Left collapse-then-parent, Enter selects; the stop follows arrows and outside selection; an unbuilt row scrolls into view (step 9) | `[Coverage: WIDGET]` (`test/features/hierarchy/widgets/hierarchy_tree_panel_test.dart` — keyboard group) |
  | A hierarchy row is one named button with expanded / selected state and a focus ring; the chevron is out of the Tab order (step 9) | `[Coverage: WIDGET]` (`test/features/hierarchy/widgets/hierarchy_tree_row_test.dart`, `test/accessibility/screen_reader_test.dart` design-open transcript) |
  | Double-click still pushes into the scope and clears the selection | `[Coverage: WIDGET]` (same group — "a double click still pushes into the scope and clears") |
  | Perceived responsiveness on a real design (no dead zone, second click not swallowed) | `[Coverage: MANUAL]` (steps 5–7) |

---

## 4.6 Design search — substring / glob / regex over the elaborated design

- **What it does.** Cmd+F opens `SearchDialog`; `DesignSearchService` matches substring / glob / regex over the elaborated design (module / instance / net / port names); selecting a result navigates to the owning scope. The dialog debounces keystrokes. The dialog mounts under the root navigator, so `SearchDialog.show` is handed the **active tab's** `ProviderContainer` and wraps its subtree in an `UncontrolledProviderScope`; the search reads and applies against the active tab's `hierarchyTreeProvider` / `selectedElementProvider` / `traceOverlayProvider`, not the empty root scope. The result list is keyboard-drivable: ArrowUp / ArrowDown move a tinted highlight while focus stays in the query field, and Enter activates the highlighted row (Enter pressed inside the 200 ms debounce window runs the pending search instead, so a fast typist never activates a stale row).
- **Setup.** A loaded design.
- **Steps and expected behavior.**
  1. Cmd/Ctrl+F. Expected: the search dialog opens. (The chord is the platform default for `openSearch`; the toolbar magnifier and the palette entry open the same dialog.)
  2. Type a substring. Expected: results populate (debounced); each result names its owning scope; the first row is highlighted.
  3. Switch to glob / regex mode and enter a pattern. Expected: matching set updates.
  4. Select a result with the pointer. Expected: the canvas / hierarchy navigates to the result's scope.
  5. **Keyboard-only run.** Cmd/Ctrl+F, type a substring, press ArrowDown twice, press Enter — without touching the pointer. Expected: the highlight moves down two rows (scrolling the list when it moves past the visible rows), Enter closes the dialog and navigates to that row's scope exactly as a click would.
  6. **Two-tab check.** Open two designs in two tabs. In tab B, Cmd+F and search a symbol that exists only in tab B. Expected: tab B's results appear (never tab A's), and selecting one applies the selection to tab B. (Before the tab-scope fix the dialog read the empty root model and always returned zero results.)
  7. **Cells in the hierarchy filter.** Open `test/fixtures/netlist/serv_ice40/captured/serv_ice40.netlist.json.gz` (decompress it to a `.json` first, then File > Open Netlist JSON…). The field above the Hierarchy tree reads **Filter scopes and cells…**. Type `add_cy`. Expected: under the single `service` scope, eleven cell rows, each with a chip icon and its type beside the name: one `SB_DFF` and ten `SB_LUT4`. Click one. Expected: the cell is selected (its row and the canvas highlight it), the inspector shows it and the canvas centers on it, the same as choosing it in Search. Arrow down onto another cell row and press Enter. Expected: the same for that cell. Type `SB_LUT4`. Expected: the first 100 matching cells, then a **Show more** row counting the rest; activating it lists the next 100. Type `zzz_nothing`. Expected: "No scopes or cells match the filter", pointing at Search for nets. In a hierarchical design (e.g. `design_seed`), filter for an instance name: the instance stays a scope row, and clicking it shows that scope. Clear the filter: no cell rows remain.
- **Edge cases.** An invalid regex does not crash the dialog (falls back / reports no match rather than throwing). An empty query yields no results, not a full dump. With no tab open, Cmd+F is a no-op (no active-tab container to scope to). Enter with an empty result list is inert (the dialog stays open). ArrowUp on the first row / ArrowDown on the last row keeps the highlight where it is rather than wrapping.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `DesignSearchService` substring / glob / regex matching | `[Coverage: UNIT]` (`test/services/search/design_search_service_test.dart`) |
  | `SearchDialog` debounce + locale sweep + active-tab-container scoping | `[Coverage: WIDGET]` (`test/features/search/widgets/search_dialog_test.dart` — the "scopes to the passed active-tab container" group proves the dialog searches and applies against the passed container, not the ambient root scope) |
  | Non-empty results for a real design (instance / cell / net) | `[Coverage: WIDGET]` (`test/features/search/widgets/search_dialog_test.dart`, "over a loaded fixture netlist" — parses `test/fixtures/netlist/design_seed/generated/design_seed.netlist.json` through `YosysJsonParser` and asserts hits for the instance `u_cpu`, the cells `dma_reg` / `pc_reg`, and the net `clk`; the locale sweep repeats the search in every supported locale) |
  | ArrowUp / ArrowDown highlight + Enter activation | `[Coverage: WIDGET]` (`test/features/search/widgets/search_dialog_test.dart`, "keyboard activation") |
  | Cmd/Ctrl+F bound to `openSearch` | `[Coverage: UNIT]` (`test/core/shortcuts/netcrux_action_test.dart`, "design search binding is Ctrl/Cmd+F") |
  | Result-select → live scope navigation | `[Coverage: MANUAL]` — driven navigation is exercised via the toolbar/palette Search opener; the end-to-end jump is not yet in an integration test. |
  | Hierarchy filter lists matching primitive cells (by name or type) under their scope, never an instance; a page of 100 then a counting Show more row; no cell rows without a filter; serv_ice40 `add_cy` gives eleven cells (one `SB_DFF`, ten `SB_LUT4`) in `service` (step 7) | `[Coverage: UNIT]` (`test/features/hierarchy/widgets/hierarchy_tree_panel_test.dart`, "filtered cell rows" group) |
  | A cell row shows its type and is one named node; click or Enter selects the cell and requests the reveal; Show more lists the next page; the new no-match message (step 7) | `[Coverage: WIDGET]` (`test/features/hierarchy/widgets/hierarchy_tree_panel_test.dart`, "filtered cell rows in the panel" group; `test/features/hierarchy/widgets/hierarchy_leaf_row_test.dart`) + `[Coverage: MANUAL]` (the canvas centering on the chosen cell in a live window) |

---

## 4.7 One-step tracing — fanin / fanout overlay

- **What it does.** With an element selected, `[` traces fanin and `]` traces fanout; the overlay dims everything off the traced cone and Esc clears it. `TraceService` computes the one-step neighbor set; `TraceOverlayNotifier` holds the per-tab overlay state; the painter renders the dim path. (This is the open-core one-step tracer; the Pro cone-of-influence multi-hop trace is a separate seam, §7.)
- **Setup.** A loaded design with a cell or net selected.
- **Steps and expected behavior.**
  1. Select a cell, press `]`. Expected: the fanout neighbors stay lit; everything else dims.
  2. Press `[`. Expected: the fanin neighbors are highlighted instead.
  3. Press Esc. Expected: the overlay clears; the schematic returns to full brightness.
  4. **Zoom to Selection.** With nothing selected, open the Navigate menu and the toolbar. Expected: **Zoom to Selection** is greyed out, and the command palette does not list it. Select a cell, pan it off screen and press `Z` (or the toolbar button beside Zoom to Fit, or Navigate > Zoom to Selection). Expected: the canvas centers on the cell at a readable zoom. Shift-click a second cell far from the first and press `Z`. Expected: both are in view. Select a cell with a wide fanout, press `]`, then `Z`. Expected: every highlighted cell and wire is on screen. Choose a cell in Search (or in the filtered Hierarchy tree), pan away, press `Z`. Expected: the canvas returns to it. Click into the Hierarchy filter and type `z`. Expected: the letter goes into the field and the camera does not move. On Windows / Linux the Navigate menu shows `Z` beside the item; on macOS the menu bar shows no key there (bare keys are not macOS menu accelerators), and the toolbar tooltip and the palette show it. Rebind it in Settings > Keyboard Shortcuts: the new key works.
- **Edge cases.** Tracing with nothing selected is a no-op. The overlay is per-tab (switching tabs does not carry the overlay across). Zoom to Selection on a lone straight wire still frames it (the box is widened to a minimum size).
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `TraceService` fanin / fanout neighbor computation; `TraceOverlay` state | `[Coverage: UNIT]` (`test/services/schematic/trace_service_test.dart`) |
  | Per-tab overlay isolation | `[Coverage: UNIT]` (`test/services/workspace/netcrux_tab_overrides_test.dart`, `traceOverlayProvider` group) |
  | `[` / `]` / Esc key wiring on a live canvas + dim-path render | `[Coverage: MANUAL]` — the service + state are unit-covered; the keyboard-to-paint round-trip is a visual check. |
  | Zoom to Selection bounds: one cell, a multi-selection, a pin's host cell, a boundary port, every routed segment of a selected net, everything an overlay highlights, a minimum extent (step 4) | `[Coverage: UNIT]` (`test/features/viewer/selection/selection_bounds_test.dart`) |
  | Zoom to Selection camera: a lone cell at the comfort zoom, a trace fitted in view, no-op with nothing selected or no canvas (step 4) | `[Coverage: UNIT]` (`test/features/viewer/services/zoom_to_selection_controller_test.dart`) |
  | Zoom to Selection on the toolbar, Navigate menu and palette, open core, disabled without a selection; bare `Z` default that a text field does not lose (step 4) | `[Coverage: UNIT]` (`test/core/shortcuts/netcrux_action_descriptors_test.dart`, "zoomToSelection" group; `test/core/shortcuts/shortcut_bindings_test.dart`) + `[Coverage: WIDGET]` (`test/core/shortcuts/shortcut_manager_widget_test.dart`) + `[Coverage: MANUAL]` (step 4 framing on a live canvas) |

---

## 4.8 Export — PNG / SVG / JSON

- **What it does.** The current scope exports three ways: PNG via `RenderRepaintBoundary.toImage` (`SchematicExportController.exportPng`, reading the per-tab `schematicCanvasKeyProvider`), SVG via programmatic generation (`SvgExporter`), and a JSON dump that re-emits the current scope's portion of the Yosys JSON.
- **Setup.** A loaded, laid-out design.
- **Steps and expected behavior.**
  1. Export PNG. Expected: a raster of the current schematic is written to the chosen path.
  2. Export SVG. Expected: a vector file whose text (labels) is escaped and whose geometry matches the on-screen layout.
  3. Export JSON. Expected: a Yosys-JSON dump of the current scope that re-opens as the same design (round-trips — §3.1).
- **Edge cases.** Export before a design is laid out is guarded (the PNG controller early-returns rather than capturing an empty boundary). SVG text with `<`, `>`, `&` is XML-escaped.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `SchematicExportController` all three flows end-to-end — real file written and its content asserted (PNG raster, JSON scope slice), the pre-picker guards (no canvas key / not a RepaintBoundary / no graph / no design), picker cancellation writing nothing, and an unwritable destination reporting failure. `SchematicExportController` takes an injectable `pickSavePath` so the platform save dialog is the only part left unautomated. | `[Coverage: WIDGET]` (`test/features/viewer/services/schematic_export_controller_test.dart`) |
  | `SvgExporter.toSvg` geometry + `svgEscape` XML-escaping | `[Coverage: UNIT]` (`test/services/export/svg_exporter_test.dart`) |
  | JSON-dump round-trip (parse → emit → re-parse structural equivalence) | `[Coverage: UNIT]` (`test/property/netlist_round_trip_test.dart`) |
  | The platform save dialog itself (default file name, extension filter, parent-window locking) and the visual fidelity of the rasterized PNG / rendered SVG | `[Coverage: MANUAL]` |

---

## 4.9 Session save / load — the `.netcrux` file

- **What it does.** A session captures the viewer state to a versioned `.netcrux` JSON with forward-compatible deserialization. `NetcruxSession` silently ignores unknown fields and rejects unknown *versions* with a snackbar; `SessionController` opens a `.netcrux` by path (adding it as a tab). `.netcrux` paths in the recent list re-open as sessions. (The session payload also carries optional `bookmarks` / `annotations`, §7.5.)
- **Setup.** A loaded design.
- **Steps and expected behavior.**
  1. In a design with at least two levels, push into a child scope, expand a row below it, select a cell, zoom and pan away from the fit. Save session. Expected: a `.netcrux` file is written.
  2. Close the tab (or quit), then open the session (`--session`, File → Open Project…, or File → Open Session… into another tab showing a different design). Expected: the design elaborates, and only then the saved scope opens, the expanded rows and selection return, and the canvas shows the saved zoom and pan — not fit-to-view, not the root.
  3. Edit the design so the saved scope's instance is renamed, re-open. Expected: the tab opens at the root, fitted to the view.
  4. Hand-edit the file's `version` to a future integer, re-open. Expected: a snackbar rejects it (forward-incompatible), rather than mis-parsing.
- **Edge cases.** An unknown *field* (from a newer build) is silently ignored — forward compatibility. A malformed body is reported, not silently blank. A session whose sources fail to elaborate shows the tab's error; selection and camera are applied, scope and expansion are not. The saved camera is consumed by the first layout: if the user navigates away before the saved scope lays out, the camera is dropped rather than applied to a later visit.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `NetcruxSession` toJson/fromJson round-trip; unknown-field ignore; unknown-version reject; empty bookmarks/annotations defaults | `[Coverage: UNIT]` (`test/domain/models/session/netcrux_session_test.dart`) |
  | `SessionController.openByPath` (error paths); `apply` waits for elaboration before scope, expansion, selection and the pending camera; restoring into a tab showing a different design; an unresolvable scope leaves the fit | `[Coverage: UNIT]` (`test/services/session/session_controller_test.dart`) |
  | The canvas reinstates a pending camera for its scope instead of fitting, and drops one for another scope | `[Coverage: WIDGET]` (`test/features/viewer/widgets/schematic_fit_to_view_test.dart`) + `[Coverage: UNIT]` (`test/features/viewer/providers/viewport_transform_notifier_test.dart`) |
  | Full save → re-import via the File menu on a live app | `[Coverage: INTEGRATION_TEST]` — see §4.1.3 (`integration_test/session/session_export_round_trip_test.dart`). |

---

## 4.10 Settings screen — master-detail shell + persisted categories

- **What it does.** Settings adopts the suite-shared `crux_settings_ui` dual-pane master-detail shell (`CruxSettingsMasterDetail`: category rail + detail pane, responsive collapse to list→detail on narrow widths). Categories: **General** (`AutoReloadMode`, **Restore tabs on launch** — §4.1.17, automatic update check), **Appearance** (language + `crux_theme` presets/overrides/packs; brightness follows the active preset), **Engines** (Yosys path mode + custom-path `yosys -V` probe), **Editors** (the editor command for inbound open-source requests), **CXP Cross-Probe** (CXP enable / port / status). `AutoReloadMode` persists via `crux_settings`, and the active preset via `AppSettings.core.activeThemeName`, whose brightness drives `MaterialApp.themeMode` live.
- **Setup.** Any build; open Settings (Cmd/Ctrl+,).
- **Steps and expected behavior.**
  1. Open Settings on a wide window. Expected: the dual-pane rail + detail shell renders.
  2. Narrow the window. Expected: it collapses to a single column (list → detail), no divider.
  3. Pick a preset of the other brightness. Expected: chrome re-tints live and the choice persists across restart.
  4. Set a custom Yosys path in Engines. Expected: the debounced `yosys -V` field reports the detected version or an "invalid path" helper.
- **Edge cases.** A toggle that would empty a required set falls back to a safe default rather than an empty selection. Persisted settings round-trip through `NetcruxSettingsCodec` under `netcrux.*` keys — except the fields composed from `CoreSettings`, which keep the suite-shared `settings.*` namespace so one `defaults write` key means the same thing in every Crux product (`settings.restoreTabsOnLaunch` is the one a user is most likely to reach for).
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | Settings screen uses the dual-pane shell wide / collapses narrow + locale sweep | `[Coverage: WIDGET]` (`test/features/settings/screens/settings_screen_test.dart`) |
  | `AppSettingsNotifier` persistence (theme mode, auto-reload, recent files, panel layout) | `[Coverage: UNIT]` (`test/features/settings/providers/app_settings_provider_test.dart`) |
  | `NetcruxSettingsCodec` round-trip under `netcrux.*` keys | `[Coverage: UNIT]` (`test/services/settings/netcrux_settings_codec_test.dart`) |
  | Settings → General “Restore tabs on launch” row — default, persisted value, write-through, 44 dp target, locale sweep | `[Coverage: WIDGET]` (`test/features/settings/screens/settings_restore_tabs_tile_test.dart`) |
  | Yosys custom-path resolution + `--yosys-path` CLI override | `[Coverage: UNIT]` (`test/services/yosys/yosys_executable_provider_test.dart`, `test/core/cli/cli_arg_parser_yosys_path_test.dart`) |
  | Live debounced `yosys -V` validation field | `[Coverage: MANUAL]` — needs a real Yosys binary and the debounce timer. |

---

## 4.11 Auto-reload — re-elaborate on source change

- **What it does.** `SourceFileWatcher` (over the cross-suite `crux_file_watcher`) watches a tab's source files; on change it honors `AutoReloadMode` (auto = re-elaborate silently; prompt = surface a Reload snackbar action; off = ignore). Under multi-tab, the watcher fires per-tab: only the tab(s) referencing the changed source(s) re-elaborate.
- **Setup.** Open a design in tab A and an unrelated design in tab B; set AutoReloadMode = auto in Settings → General.
- **Steps and expected behavior.**
  1. Edit and save tab A's source file. Expected: tab A re-elaborates; tab B is untouched (its diagnostics drawer does not change).
  2. Switch AutoReloadMode to prompt, edit the file again. Expected: a Reload snackbar action appears instead of an automatic re-elaboration.
  3. Switch to off. Expected: edits are ignored until a manual re-open.
- **Edge cases.** Editing only an `include`d header does not necessarily re-fire (the same accepted blind spot as the elaboration-cache fingerprint, §4.3). The watcher state is per-tab and does not bleed across tabs.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `sourceReloadEventsProvider` + `sourceFileWatcherProvider` are independent per-tab | `[Coverage: UNIT]` (`test/services/reload/source_file_watcher_per_tab_test.dart`) |
  | Live file-watch → re-elaborate with AutoReloadMode auto / prompt / off | `[Coverage: MANUAL]` — the per-tab isolation is unit-covered; the OS file-watch → re-elaboration round-trip is a live check. |

---

## 5. Project Files, VHDL, Web Read-Only

This section covers the project/session file formats, filelist import, VHDL (and mixed-language) elaboration through a standalone `ghdl --synth` lowering step, the bounded-memory streaming JSON parser, the web read-only viewer, and Yosys diagnostic surfacing. All items are populated below: the web read-only viewer in §5.1, then `.netcrux-project` (§5.2), `.f` filelist import (§5.3), VHDL via `ghdl --synth` (§5.4), mixed-language designs (§5.5), the JSON streaming parser (§5.6), and Yosys diagnostic surfacing (§5.7).

### 5.1 Web schematic viewer — loading a netlist, client-side elkjs layout

**What it does (plain language).** NetCrux ships a read-only browser build (`app.netcrux.app`). It cannot run Yosys — browsers can't spawn subprocesses — so it does not elaborate HDL. Instead it takes a **Yosys netlist JSON** (the elaborated netlist someone already produced with `yosys -p 'read_verilog …; proc; write_json out.json'`) and renders it as a navigable schematic. A netlist arrives two ways: the start screen's **Open Netlist JSON…** button (also on the toolbar and in the palette), which picks a file the page reads through a `blob:` URL, and the `?json=<url>` deep link, which `WorkspaceScreen` opens in a tab before applying the `#scope=` / `#sig=` hints through `WebDeepLink`. Both go through `PrebuiltNetlistLoader`, which on web fetches the location and parses in place (no isolate). Actions that need a local file system, a subprocess or a socket — Open Project / Source Files / Session / Workspace, Save Session, Save Workspace As, Import Filelist, the three exports, the Cross-Probe panel, Check for Updates, Quit — and every Pro action are hidden from the toolbar, palette and keyboard (`NetcruxActionContext.isBrowser`). The layout is computed **client-side in the browser** with the same vendored `elk.bundled.js`: elkjs runs natively, so there is no flutter_js and no background isolate on web — `elk_web_solver_web.dart` `await`s elkjs's real `layout()` Promise via `dart:js_interop`.

**Setup.** Build: `flutter build web` from `netcrux/` (open-core; the Pro overlay has no web build). Serve `build/web/` from any static host, with a Yosys netlist JSON served from the same origin or a CORS-enabled one (e.g. `test/fixtures/netlist/design_seed/generated/design_seed.netlist.json`, and a denser one like a picorv32 netlist).

**Step-by-step expected behavior.**
1. Open the viewer with no query. Expected: the start screen shows one button, **Open Netlist JSON…**, and a line saying HDL needs the desktop app; the toolbar has no Open Project, Open Source Files, Save Session or Cross-Probe buttons.
2. Open `…/?json=<url-of-design_seed.netlist.json>`. Expected: a tab named `design_seed.netlist.json` opens, the hierarchy tree populates, the top module auto-selects, and the status bar shows the file name, top module and cell count with no "Yosys not found" segment.
3. The schematic canvas shows the "Laying out the schematic… (N cells)" progress indicator, then paints the laid-out schematic — boxes for cells/ports, routed datapath edges.
4. Open `…/?json=<url>#scope=top.u_cpu&sig=alu_y`. Expected: the `u_cpu` scope opens, `u_alu` (the cell driving `alu_y`) is selected, and the canvas centres on it.
5. Open `…/?json=<a URL on a server without CORS headers>`. Expected: the tab's error view, plus a snackbar saying the server must allow cross-origin requests.
6. Click **Open Netlist JSON…** and pick a netlist file. Expected: a tab named after the file renders it; the status bar shows the file's name, not a blob id.
7. Navigate into a child scope in the hierarchy tree — it lays out and paints too (each solve is a fresh browser elkjs call; the in-memory cache makes A→B→A instant).
8. Load a denser scope (~1 600 cells, picorv32) — it lays out in the browser (single-threaded blob Web Worker); expect a longer solve than desktop QuickJS but a correct, readable schematic.

**Diagnostics-assisted verification.** With a malformed netlist, the tab's error view shows the parse error. With a malformed/empty layout input, the canvas surfaces a `LayoutException` (the web solver throws the same exception type as desktop). An elkjs constructor failure surfaces as `elkjs constructor threw: <msg>`.

**Edge cases.**
- **Blob Web Worker / CSP.** Default `new ELK()` runs the solver in a Web Worker built from an inlined blob. The static viewer ships no restrictive CSP, so `worker-src blob:` is permitted. If a self-hoster adds a strict CSP that blocks blob workers, `new ELK()` fails → `LayoutException` on first solve. Document `worker-src blob:` as a hosting requirement.
- **Large netlist memory.** The netlist JSON is copied into the browser heap; very large designs (hundreds of MB) may exhaust the tab. Same soft ceiling posture as the desktop streaming parser.
- **No disk cache on web.** `LayoutDiskCache` is null on web (no cross-session persistence); the in-memory cache still elides re-solves within a session. The workspace is not persisted either, so an uploaded netlist does not come back after a reload.
- **Hints that name nothing** are ignored; the design stays at its root.

**Tier-gate scenarios.** The web viewer is Open-Core-only; Pro actions are hidden there rather than badged, since no licence can unlock them in a browser. This is unaffected by `kBetaPeriod` (beta vs post-beta).

**Automation Assessment.**

| Behavior | Automation |
|----------|------------|
| `?json=` opens a tab on the URL, `#scope=` / `#sig=` land, a failed fetch explains itself, the start screen offers only a netlist — booted through the real `NetcruxApp` with the browser seams set | `[Coverage: WIDGET]` (`test/features/workspace/screens/workspace_web_launch_test.dart`) |
| Scope-path parsing, cell and driven-net reveal, unresolvable hints | `[Coverage: UNIT]` (`test/features/workspace/services/web_deep_link_test.dart`) |
| Desktop-only and Pro actions hidden on every surface and inert on the keyboard in the browser context | `[Coverage: UNIT]` (`test/core/shortcuts/netcrux_action_descriptors_test.dart`, `test/core/shortcuts/shortcut_manager_widget_test.dart`) + `[Coverage: WIDGET]` (`test/core/shortcuts/action_surface_conformance_test.dart`) |
| Netlist read and parsed in place, without isolate or Yosys, for any location | `[Coverage: UNIT]` (`test/features/project/providers/loaded_netlist_provider_test.dart`, `test/services/yosys/prebuilt_netlist_loader_test.dart`) |
| In a real browser: no Yosys, no isolate, and no CXP server or discovery directory | `[Coverage: CI]` (`test/services/yosys/prebuilt_netlist_loader_web_test.dart`, `test/features/remote/providers/cxp_server_provider_web_test.dart`, run by `tool/run_web_tests.sh` in CI's web job) |
| In a real browser: a tab's URL, `blob:` id or file name is its identity, verbatim and case-sensitive; a project opens under no organization policy with no override | `[Coverage: CI]` (`test/services/workspace/netcrux_workspace_codec_web_test.dart`, `test/core/policy/audit_emission_web_test.dart`, run by `tool/run_web_tests.sh`) |
| Off-web resolves the stub backend (`kElkWebSolverAvailable == false`), keeping the isolate path | `[Coverage: UNIT]` (`test/services/layout/elk_web_solver_stub_test.dart`) |
| Web build compiles with the `dart:js_interop` solver (dart2js) | `[Coverage: CI]` (`flutter build web` in `web-deploy.yml`) |
| Browser actually fetches, lays out and paints a netlist end-to-end | `[Coverage: MANUAL]` — steps 1–8; a headless-Chrome screenshot of the release bundle serving `?json=` is the quick check. No committed Chrome-headless harness in netcrux yet — **automation gap**. |
| Blob-worker/CSP failure surfaces as `LayoutException` | `[Coverage: MANUAL]` — edge case above. |

### 5.2 `.netcrux-project` file — the canonical project format

- **What it does.** The project file (`.netcrux-project`, distinct from a `.netcrux` session) captures a source list, top module, defines, include paths, and common Yosys options. `NetcruxProject` is the immutable domain model; `NetcruxProjectFileReader` does forward-compatible deserialization (unknown fields ignored, unknown versions rejected with a snackbar). No command in the app writes a project file — a project is written by hand or by another tool. `NetcruxProjectFileWriter` (pretty-printed two-space JSON, atomic temp-file-rename writes) is the reader's round-trip partner in the unit tests and has no caller in the app. `currentProjectProvider` is the canonical elaboration input. "Open Project…" accepts both `.netcrux-project` and `.netcrux` (legacy session compat).
- **Setup.** The golden fixture `test/fixtures/project/golden_v1.netcrux-project`.
- **Steps and expected behavior.**
  1. Open `golden_v1.netcrux-project`. Expected: the project's sources / top / defines / include paths drive elaboration.
  2. Hand-edit the file's `version` to a future integer, re-open. Expected: rejected with a snackbar. Add an unknown field. Expected: silently ignored.
- **Edge cases.** An unknown field from a newer build is dropped, not fatal.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `NetcruxProject` model round-trip + equality | `[Coverage: UNIT]` (`test/domain/models/project/netcrux_project_test.dart`) |
  | Reader/Writer forward-compat (unknown field ignore, unknown version reject), pretty-print, atomic write | `[Coverage: UNIT]` (`test/services/project/netcrux_project_file_test.dart`) |
  | Live Open Project → elaborate on a real host | `[Coverage: MANUAL]` — needs Yosys; the format is unit-covered. |

### 5.3 `.f` filelist import — Vivado-style filelists

- **What it does.** `FilelistReader` parses Vivado-style `.f` files: source paths, `+define+NAME[=VALUE]`, `+incdir+PATH`, recursive `-f <other>.f`, `//` + `#` comments, and `$VAR` / `${VAR}` env-var expansion. Cycles raise `FilelistCycleException`; missing nested filelists raise `FilelistNotFoundException`. `FilelistReader.readAsProject` materialises a `NetcruxProject`. `NetcruxAction.importFilelist` (Cmd/Ctrl+Shift+I) plus an "Import Vivado Filelist…" empty-canvas button invoke it.
- **Setup.** The six committed fixtures under `test/fixtures/filelist/`.
- **Steps and expected behavior.**
  1. Import a `.f` with sources + `+define+` + `+incdir+`. Expected: a `NetcruxProject` with those sources, defines, and include dirs.
  2. Import a `.f` that recursively `-f`s another. Expected: the nested list is expanded inline.
  3. Import a `.f` referencing `$VAR`. Expected: the env var is expanded.
- **Edge cases.** A self-referential / mutually-recursive `-f` chain raises `FilelistCycleException` (no infinite loop). A missing nested `.f` raises `FilelistNotFoundException`. Comments (`//`, `#`) are stripped.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `FilelistReader` parse (sources / defines / incdirs / recursive `-f` / comments / env-var expansion), cycle + not-found exceptions, `readAsProject` | `[Coverage: UNIT]` (`test/services/filelist/filelist_reader_test.dart`) |
  | Import action / empty-canvas button dispatch | `[Coverage: WIDGET]` (`test/features/viewer/widgets/netcrux_toolbar_test.dart` / palette dispatch, §4.1.9) |

### 5.4 VHDL via standalone `ghdl --synth` — lowering to Verilog + bundled engines

- **What it does.** VHDL sources are lowered to Verilog before Yosys runs. `crux_yosys`'s `YosysSourceFile` / `YosysSourceLanguage` classifies each input as Verilog / SystemVerilog / VHDL; for VHDL inputs `YosysRunner` first runs `ghdl --synth --out=verilog <vhdl files> -e <top>` as a separate process, and the Yosys script reads the emitted Verilog with `read_verilog`. No GHDL Yosys plugin is involved: the script never contains `plugin -i ghdl`, so a plain GHDL build on `PATH` is enough. `tool/bundled_engines.yaml` pins yosys 0.42 and ghdl 4.1.0 with per-platform URLs (the plugin is deliberately absent); `BundledBinaryResolver` (consulting `NETCRUX_BUNDLED_BIN_DIR`) backs `effectiveYosysExecutableProvider`'s bundled mode.
- **Setup.** VHDL fixtures under `test/fixtures/vhdl/` (`and2`, `adder4`, `fsm`); a host with `ghdl` and `yosys` on PATH for the live path.
- **Steps and expected behavior.**
  1. Open `test/fixtures/vhdl/and2.vhd` (VHDL). Expected, with ghdl available: ghdl lowers the VHDL, Yosys reads the result, and the design renders.
  2. Inspect the generated commands (no subprocess needed). Expected: `YosysRunner.buildGhdlSynthArguments` yields `--synth --out=verilog <vhdl files> -e <top>`; the Yosys script reads Verilog and contains no `plugin -i ghdl`.
- **Edge cases.** A missing `ghdl`, or a GHDL analysis / synthesis error, fails the run; the stderr carrying the ghdl diagnostic surfaces through the non-zero-exit envelope (`elaborationErrorNonZeroExit`, §4.1.7) with the raw text under **Details**. The bundled-mode resolver falls through cleanly when `NETCRUX_BUNDLED_BIN_DIR` is unset.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | ghdl lowering arguments and a plugin-free Yosys script, without a subprocess | `[Coverage: UNIT]` (`test/services/project/mixed_language_script_test.dart`) |
  | `BundledBinaryResolver` path resolution via `NETCRUX_BUNDLED_BIN_DIR` | `[Coverage: UNIT]` (`test/services/engines/bundled_binary_resolver_test.dart`) |
  | Real VHDL → ghdl → yosys → parse end-to-end | `[Coverage: INTEGRATION_TEST]` (`test/integration/vhdl_pipeline_test.dart`; skipped with a reason when `ghdl` is absent) + `[Coverage: MANUAL]` (live host) |

### 5.5 Mixed-language designs — Verilog + VHDL in one project

- **What it does.** A single project can mix Verilog and VHDL. `NetcruxProject` carries `sourceFileLanguages: Map<String, NetcruxSourceLanguage>` (auto-detected from file extension by default). The VHDL files are lowered by the same standalone `ghdl --synth` step as §5.4, and Yosys reads the Verilog sources together with the lowered VHDL before `hierarchy -check`, so both languages end in one netlist.
- **Setup.** The mixed fixture under `test/fixtures/mixed/` (a Verilog top instantiating a VHDL submodule); ghdl and yosys on PATH for the live path.
- **Steps and expected behavior.**
  1. Open the mixed fixture. Expected, with ghdl available: both languages elaborate into one netlist; the Verilog top shows its VHDL submodule.
  2. Inspect the generated commands. Expected: the ghdl arguments name only the VHDL file; the Yosys script reads Verilog and loads no plugin.
- **Edge cases.** Extension auto-detect drives per-file language classification; an unrecognized extension is handled per `NetcruxProject.resolveLanguage`. A ghdl failure surfaces as in §5.4.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | Mixed Verilog+VHDL lowering arguments and Yosys read shape | `[Coverage: UNIT]` (`test/services/project/mixed_language_script_test.dart`) |
  | Real mixed-language → ghdl + yosys end-to-end | `[Coverage: INTEGRATION_TEST]` (`test/integration/mixed_pipeline_test.dart`; skipped when `ghdl` is absent) + `[Coverage: MANUAL]` (live host) |

### 5.6 JSON streaming parser — bounded-memory netlist load

- **What it does.** `StreamingYosysJsonReader` walks `write_json` output one module at a time via brace-depth tracking (string-escape aware) and decodes each module's sub-document independently, so peak memory is bounded by O(largest single module) + the accumulated `modules` map rather than the whole document. `readFile` / `readStream` cover file + stream inputs; a `CancellationToken` lets the UI drop an in-flight elaboration when the user opens a different design. `loadedNetlistProvider` uses the streaming reader by default; cross-parser equivalence is asserted against the in-memory `YosysJsonParser`.
- **Setup.** The pipeline fixtures (and2 / adder4 / fsm) and a large fixture (e.g. `test/fixtures/netlist/chain_10k/`).
- **Steps and expected behavior.**
  1. Open a large design. Expected: it parses without loading the entire JSON string into a single decode; memory stays bounded.
  2. Open design A then immediately open design B mid-parse. Expected: A's in-flight parse is cancelled via the `CancellationToken`; B loads.
- **Edge cases.** A nested type error surfaces as a typed `YosysJsonParseException` naming the module (never a raw error). Streaming output must match the in-memory parser byte-for-byte on the reference fixtures.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `StreamingYosysJsonReader` brace-depth walk, per-module decode, cancellation, cross-parser equivalence | `[Coverage: UNIT]` (`test/services/yosys/streaming_yosys_json_reader_test.dart`) |
  | Malformed input → typed `YosysJsonParseException` with the module name | `[Coverage: FUZZ]` (`test/services/yosys/yosys_json_fuzz_test.dart` + `test/fixtures/netlist/malformed/`) |
  | Streaming reader is the default in the load pipeline | `[Coverage: UNIT]` (`test/features/project/providers/loaded_netlist_provider_test.dart`) |

### 5.7 Yosys diagnostic surfacing — the Tab Diagnostics drawer

- **What it does.** Yosys warnings / errors appear in the per-tab **Tab Diagnostics drawer** (Cmd+3), mirroring the WaveCrux diagnostics-drawer pattern. `elaborationStderrProvider` captures the run's stderr on success *and* failure (Yosys writes warnings even on healthy runs); `elaborationDiagnosticsProvider` parses it via the `crux_yosys` diagnostic parser; `elaborationDiagnosticFilterProvider` holds the severity chips (errors / warnings / info — a toggle that would empty the set resets to all-on). The drawer (`tab_diagnostics_drawer.dart`) renders severity icon + `file:line` + per-row copy + a "Copy Report" structured bundle. Rows with a location copy it; rows without extract a module name and select it in the hierarchy.
- **Setup.** A design that emits Yosys warnings, with Yosys on PATH.
- **Steps and expected behavior.**
  1. Open the design; press Cmd+3. Expected: the drawer lists the run's warnings with severity icon + `file:line`.
  2. Toggle the severity chips. Expected: the row set filters; toggling off the last remaining severity resets to all-on (never an empty list).
  3. Click a row with a location. Expected: the `file:line` is copied. Click a location-less row. Expected: its module is selected in the hierarchy.
  4. "Copy Report". Expected: a structured plain-text bundle lands on the clipboard.
  5. **Two-tab isolation.** With tab A's design elaborated, open a second tab on a different design (or an empty tab) and press Cmd+3. Expected: each tab's drawer shows only its own run's diagnostics; narrowing the severity chips in tab A leaves tab B's chips all-on and tab B's row set untouched.
- **Edge cases.** Warnings appear even when elaboration *succeeds* (stderr is captured on the success path). A fatal failure where Yosys never ran surfaces the fatal-error banner (§4.1.7) above any parsed diagnostics. All four providers — the stderr holder, the severity filter, and the two derived views (`elaborationDiagnosticsProvider`, `filteredElaborationDiagnosticsProvider`) — are re-bound per tab in `netcruxTabOverridesFactory`; the derived pair previously hoisted to the root container, where they watched an always-empty stderr, so the drawer showed no warnings at all after a successful elaboration.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `elaborationStderrProvider` / `elaborationDiagnosticsProvider` / `elaborationDiagnosticFilterProvider` (incl. empty-set reset) / filtered view | `[Coverage: UNIT]` (`test/features/project/providers/elaboration_diagnostics_provider_test.dart`) |
  | `TabDiagnosticsDrawer` renders rows, severity filter, copy actions | `[Coverage: WIDGET]` (`test/features/diagnostics/tab_diagnostics_drawer_test.dart`) |
  | Two-tab isolation of the parsed + filtered views (real `TabContainerManager` topology) | `[Coverage: UNIT]` (`test/services/workspace/per_tab_elaboration_diagnostics_scope_test.dart`) |
  | All four diagnostics providers listed in `netcruxTabOverridesFactory` | `[Coverage: STATIC]` (`test/static/per_tab_provider_scope_leak_test.dart`, transitive-closure scan) |
  | Live warnings from a real Yosys run into the drawer | `[Coverage: MANUAL]` — the providers seed synthetic stderr; end-to-end needs a real run. |

### 5.8 Opening a design as what it is — netlist JSON, `<design>.crux-project`, session

- **What it does.** Every open path hands NetCrux's pipeline the design a file describes, never the file itself as HDL. A single `.json` source is a **pre-built Yosys netlist**: `LoadedNetlist` reads and parses it through `PrebuiltNetlistLoader` (`lib/services/yosys/prebuilt_netlist_loader.dart`) and never probes for or runs Yosys. A **`<design>.crux-project`** manifest (File → Open Project…, whose filter includes the `crux-project` extension, or a positional CLI argument, matched by `CruxProjectParser.isManifestPath`) opens either its `artifacts.netlist` (preferred) or every `design.sources` entry with `design.top`; a manifest naming neither, or naming a missing netlist, or failing to parse shows a localized snackbar. A positional **design directory** opens the one manifest inside it; a directory with none, or with more than one, shows a localized error naming what it found. The legacy bare `.crux-project` still opens, followed by one localized notice naming the file to rename it to. A **`.netcrux` session** (`--session`, a positional argument, or File → Open Project…) is read first; the tab opens on the session's sources and top module and the session's view state is applied to it.
- **Setup.** `test/fixtures/netlist/design_seed/generated/design_seed.netlist.json`; a directory `uart/` with three HDL files and a `uart.crux-project` listing them with `design.top`; a saved `.netcrux` session.
- **Steps and expected behavior.**
  1. `netcrux path/to/design_seed.netlist.json` with Yosys **uninstalled** (or `--yosys-path /nonexistent`). Expected: the schematic renders with top `top`; the Diagnostics drawer is empty; no "Yosys not found" error view.
  2. `netcrux path/to/uart/uart.crux-project` naming the three sources and `top`. Expected: one tab named after the manifest's `name`; the status bar reports the declared top; all three files elaborate (a module defined only in the third file resolves). Close the tab and run `netcrux path/to/uart`. Expected: the same design opens. On macOS, File → Open Project… shows `uart.crux-project` as selectable.
  3. Edit the manifest to add `artifacts.netlist: build/top.json` pointing at a copy of the seed netlist. Reopen. Expected: the netlist renders without Yosys running. Delete the netlist file and reopen. Expected: a snackbar naming the missing netlist; no tab opens.
  4. `netcrux --session review.netcrux`, and separately File → Open Project… on the same file. Expected: a tab on the session's design — never a Yosys syntax error naming `review.netcrux`.
  5. Copy `uart.crux-project` to `.crux-project` in the same directory and run `netcrux path/to/uart`. Expected: an error naming both files; no tab opens. Delete `uart.crux-project` and run `netcrux path/to/uart/.crux-project`. Expected: the design opens, and one notice says to rename the file to `uart.crux-project`.
- **Edge cases.** Two or more `.json` files are not a netlist and go to Yosys as before. In a build that cannot elaborate (the web viewer) every single-location design is read as a netlist and a multi-file HDL project reports the engine as unavailable. Recents record the manifest, not what it resolved to, so reopening a manifest re-reads it.
- **Automation Assessment.**

  | Test | Coverage |
  |---|---|
  | `.json` source parsed without Yosys; missing file; browser branch; HDL in a build that cannot elaborate | `[Coverage: UNIT]` (`test/features/project/providers/loaded_netlist_provider_test.dart`, `test/services/yosys/prebuilt_netlist_loader_test.dart`) |
  | Session, positional session, multi-source manifest with top, netlist manifest, unusable manifest, design directory, ambiguous and empty directory, legacy file-name notice shown once — booted through the real `NetcruxApp` launch path | `[Coverage: WIDGET]` (`test/features/workspace/screens/workspace_open_design_test.dart`) |
  | Positional `<design>.crux-project`, legacy `.crux-project`, directory and `.json` routing | `[Coverage: UNIT]` (`test/core/cli/cli_arg_parser_test.dart`) |
  | Manifest resolution precedence, typed refusals, named and legacy file names, directory lookup | `[Coverage: UNIT]` (`test/services/file_open/crux_project_resolution_test.dart`) |
  | Finder and the macOS Open dialog recognize `crux-project` | `[Coverage: MANUAL]` — step 2; the document type is declared in `macos/Runner/Info.plist`. |
  | Live elaboration of a multi-source manifest | `[Coverage: MANUAL]` — steps 2–3 need a real Yosys. |

## 6. Cross-Probing & CXP Protocol

NetCrux ships an open-core CXP peer cross-probe server: `NetcruxCxpServer` wrapping `crux_cxp`'s `LocalCxpServer` with the NetCrux-specific name resolver, the manifest writer, the discovery watcher, the inbound `request_highlight` / `request_open_source` handlers, the outbound `notify_selection` emitter, the cross-probe panel UI, and the Settings → CXP Cross-Probe controls. Pro-tier originate-cross-probe coverage (the schematic context-menu originator) is verified in the Pro overlay's own guide.

The shared `crux_cxp` package's conformance suite (in `crux-shared/packages/crux_cxp/test/conformance/`) is re-run against `NetcruxCxpServer` via `test/services/remote/cxp/netcrux_cxp_server_conformance_test.dart` — every peer that ships the protocol passes the same matrix. NetCrux pins `crux_cxp` 0.2.0 (suite item X1: connector-link inbound routing, auto-subscribe, and a transport-robustness batch — decode-fault wrapping, handshake/version-negotiation hardening, broadcast concurrent-modification safety, bounded line framing). `crux_cxp`'s own README documents the wire-level policies; §6.1/§6.2/§6.3 below cover the NetCrux-specific consequences.

### 6.1 CXP server lifecycle

**What it does.** When NetCrux launches with `cxpServerEnabled = true` in Settings → CXP Cross-Probe, the CXP server binds to localhost on the configured port (default 54323), writes a discovery manifest `netcrux-<pid>-<startedAt>.json` into the **suite-shared** directory resolved by `sharedCxpManifestDirectory()` (`~/Library/Application Support/crux/cxp/peers/` on macOS, `%APPDATA%\crux\cxp\peers\` on Windows, `${XDG_DATA_HOME:-~/.local/share}/crux/cxp/peers/` on Linux — **not** the per-app container, so any two products on one machine resolve the same directory), starts watching the same directory for peer manifests, refreshes its own manifest every ~30 s (heartbeat, so peers do not stale-prune a long-running NetCrux at their 5-minute threshold), and **dials every discovered non-self peer** (`CxpPeerConnector`) so both sides' servers see a live connection.

The connector is constructed with `server:` pointing at the live `LocalCxpServer` (`crux_cxp` 0.2.0, suite item X1). This routes every frame the connector's own outbound link receives into `server.inbound` alongside server-accepted traffic, registers the link as a reply route (so `sendTo` can answer a peer we merely dialed, even if it never dials us back), and auto-subscribes the link to `notify_selection` gossip immediately after the handshake — with zero per-product wiring. Before X1, a connector that only dialed for presence left link traffic silently dropped: a peer we discovered but who never opened a socket back to us could see us as "connected" while every request it sent us, and every broadcast we sent it, vanished unheard. See §6.2/§6.3 for the tests that pin this specifically.

**Setup.** Launch a build with default Settings. No peer needs to be running.

**Steps.**

1. Check that Settings → CXP Cross-Probe shows the CXP server enabled.
2. Open the cross-probe panel (command palette → "Show Cross-Probe Panel").
3. Verify the status row reads "CXP server running" with a tertiary-coloured dot.
4. Verify `${appSupportDir}/crux/cxp/peers/netcrux-<pid>.json` exists on disk and matches the expected manifest shape (PeerIdentity + host + port + started_at).
5. Toggle CXP off in Settings → CXP Cross-Probe. Verify the panel status flips to "CXP server disabled" and the manifest file is removed.
6. Toggle CXP back on. Verify a fresh manifest is written (same peer-id prefix, new started_at).

**Tier-gate scenarios.** None — the CXP server is open-core and ships in every build regardless of license tier.

**Automation status.** Automated via `test/services/remote/cxp/netcrux_cxp_server_test.dart` (server lifecycle, manifest write/remove, handshake, discovery add/remove, mutual connection between two connector-linked servers). `test/services/remote/cxp/cxp_connector_link_test.dart` additionally pins the X1 connector-link seam end-to-end: a request arriving purely over the link NetCrux's own connector opened (not a socket a peer dialed into us) reaches the production `CxpInboundHandler` and the ack routes back over that same link, using only real `CxpPeerConnector` / `LocalCxpServer` wiring on both sides — no hand-rolled test client. `[Coverage: INTEGRATION_TEST]` — `integration_test/remote_control/cxp_server_lifecycle_test.dart` boots the real app, asserts the default-enabled server constructs and runs (or degrades with a recorded reason), then flips `cxpServerEnabled` off → on through `appSettingsProvider` and asserts the host provider tears the server down and brings it back up.

### 6.2 notify_selection emission on tab selection

**What it does.** Whenever the user selects an element in a NetCrux schematic canvas (cell, port, boundary port, wire, or hierarchy node), the CXP server broadcasts a `NotifySelection` to every subscriber peer. Empty selection is suppressed.

**Setup.** Launch NetCrux with a small Verilog design open in the active tab. Pair with a peer that subscribes to `notify_selection` (the conformance test uses `LocalCxpClient`; a manual peer can be a WaveCrux build).

**Steps.**

1. Subscribe the peer to `notify_selection`.
2. Click a cell in the schematic. Verify the peer receives `NotifySelection(ElementKind.instance, path="<top>.<cell>:cell")` with the cell's name as `displayName`.
3. Click a port on the same cell. Verify the peer receives `NotifySelection(ElementKind.port, path="<top>.<cell>.<port>")`.
4. Click a wire. Verify `NotifySelection(ElementKind.net, path="<top>:net:<edgeId>")`.
5. Click the canvas background to clear the selection. Verify the peer receives **no** message.
6. Switch tabs to a different design. Verify the emitter now reflects the new tab's selection.

**Tier-gate scenarios.** None — receive side of cross-probe is open-core.

**Automation status.** Automated via `test/services/remote/cxp/cxp_outbound_emitter_controller_test.dart` (cell, port, wire, suppression of empty selection) against a hand-subscribed `LocalCxpClient`. `test/services/remote/cxp/cxp_connector_link_test.dart` covers the distinct X1 case those tests don't: a peer that never sends a manual `Subscribe` at all — connected only via its own `CxpPeerConnector`'s auto-subscribe — still receives the broadcast, proving the connector-link auto-subscribe path (not just the direct-subscribe path) delivers gossip. `[Coverage: INTEGRATION_TEST]` — `integration_test/remote_control/notify_selection_emission_test.dart` boots the real app, seeds a loaded design, connects a raw CXP peer to the live server's bound port, subscribes it to `notify_selection`, selects a cell through `selectedElementProvider` (the same provider the schematic canvas's tap-selection gesture handler writes to), and asserts the peer receives the correctly-shaped broadcast.

### 6.3 request_highlight receive — instance / port / scope / net

**What it does.** When a peer sends `RequestHighlight` to NetCrux, the inbound handler resolves the canonical `ElementId` through `NetcruxNameResolver` and updates the active tab's selection or hierarchy navigation accordingly. For instance / port / net kinds the handler now **pre-validates the element exists** in the active scope's graph (built from the tab's hierarchy state) before selecting — mirroring the existence check the scope kind already performs against the hierarchy. A syntactically-valid path naming an absent element (`top.nonexistent_cell`, or a real cell with an absent pin) acks `honored: false` with a "not found" reason and leaves the selection untouched, rather than acking `honored: true` while highlighting nothing.

**Setup.** Same design loaded as in 6.2.

**Steps.**

1. From the peer (e.g. WaveCrux), trigger a cross-probe to a NetCrux cell — issue `RequestHighlight(ElementId.instance, "<top>.<cell>:cell")`.
2. Verify NetCrux's inspector now shows the targeted cell as the active selection.
3. Repeat for port (`ElementKind.port`) and net (`ElementKind.net`) kinds.
4. Issue `RequestHighlight(ElementKind.scope, "<top>.<instance>")`. Verify NetCrux's hierarchy tree navigates into the named instance and the canvas re-lays out at the new scope.
5. Issue `RequestHighlight(ElementKind.scope, "<top>.no_such_instance")`. Verify NetCrux replies with `RequestHighlightAck(honored: false, reason: ...not found...)`.
6. Issue `RequestHighlight(ElementKind.instance, "<top>.no_such_cell:cell")` and (with a real cell) a port kind naming an absent pin. Verify each acks `honored: false` (`...not found...`) and the active selection is unchanged.

**Automation status.** Automated via `test/services/remote/cxp/cxp_inbound_handler_test.dart` (instance, port, scope happy + unknown-scope failure + **nonexistent-instance and absent-port existence-check failures** + no-active-tab failure) against a directly-connected `LocalCxpClient`. `test/services/remote/cxp/cxp_connector_link_test.dart` covers delivery over a `CxpPeerConnector` link instead — the case that was silently dropped pre-X1. `[Coverage: INTEGRATION_TEST]` — `integration_test/remote_control/request_highlight_navigation_test.dart` boots the real app (through the production `CxpInboundListener` wiring, not a bare `CxpInboundHandler`), seeds a loaded design, connects a raw CXP peer to the live server's bound port, and asserts an `ElementKind.instance` request updates the active tab's selection and the real `InspectorPanel` renders it, and an `ElementKind.scope` request navigates the hierarchy and the schematic re-lays-out at the new scope.

### 6.4 request_open_source — editor shell-out

**What it does.** Peers send `RequestOpenSource(filePath, line, column?)` to ask NetCrux to open the configured editor at that location. NetCrux substitutes `<file>` / `<line>` / `<column>` (and `{file}` / `{line}` for backward-compat) in the configured command template and invokes the editor.

**Setup.** Configure Settings → Editors → Editor command to a known executable (e.g. `code -g {file}:{line}`).

**Steps.**

1. From the peer, send `RequestOpenSource(/path/to/cpu.v, 42)`.
2. Verify the editor opens `cpu.v` at line 42.
3. Set the editor command to an empty string. Re-send the request. Verify the peer receives `RequestOpenSourceAck(honored: false, reason: "No editor command configured.")`.
4. Set the command to a non-existent executable (e.g. `codex {file}`). Re-send. Verify the peer receives `RequestOpenSourceAck(honored: false)` with a "Failed to launch" reason.

**Automation status.** Automated via `test/services/remote/cxp/cxp_inbound_handler_test.dart` (happy path, empty command, exit-code failure, ProcessException failure).

### 6.5 Cross-probe panel — discovery + event log

**What it does.** The cross-probe panel renders the connected peer list (sourced from the discovery watcher) and a rolling event log capturing inbound messages and presence events.

**Setup.** Launch NetCrux and a peer that writes a manifest to the same `${appSupportDir}/crux/cxp/peers/` directory.

**Steps.**

1. Verify the panel's "Peers" section initially shows "No peers connected yet."
2. Start the peer. Within ~2 seconds (discovery scan interval), the panel lists the peer.
3. Send a `RequestHighlight` from the peer. Verify the panel's "Recent events" section gains a new inbound entry with the right peer label, kind, and detail line.
4. Stop the peer. Verify the panel's peer list removes the entry within ~2 seconds.

**Automation status.** Automated via `test/services/remote/cxp/netcrux_cxp_server_test.dart` (discovery add + remove) and `test/features/remote/providers/cxp_event_log_provider_test.dart` (rolling-buffer capacity + newest-first ordering, inbound/presence capture, and the per-kind detail line, all driven over a real socket). Widget-level rendering of the panel is covered by `test/features/remote/widgets/cross_probe_panel_test.dart` (empty state + locale sweep). `[Coverage: INTEGRATION_TEST]` — `integration_test/remote_control/cross_probe_panel_discovery_test.dart` boots the real app, opens the real `CrossProbePanel` dialog, starts a second real `NetcruxCxpServer` ("peer B") sharing the manifest directory to drive a genuine two-peer manifest exchange (real files on disk, real `CxpDiscovery` scan, real symmetric `CxpPeerConnector` dial-in), and asserts the panel's Peers section renders the discovered peer and the event log records both the presence "connected" entry from peer B's handshake and an inbound message entry from a third raw peer dialing directly into the app's bound port.

### 6.5.1 Cross-probe panel — "Send selection" to a peer

**What it does.** Each peer row carries a **Send selection** button that transmits the *active tab's current schematic selection* to that one peer as a targeted `notify_selection`. The selection is translated to canonical CXP form by `resolveCxpSelection` (`lib/services/remote/cxp/cxp_selection_resolver.dart`) — the same helper the automatic broadcast emitter (`CxpOutboundEmitterController`) uses, so a targeted send and an automatic broadcast carry byte-identical element references, kinds, display names, and `netcrux.scope_path` metadata.

The panel is hosted in a dialog above the workspace shell, i.e. **outside** the active tab's provider scope, so it resolves the active tab's `ProviderContainer` through `WorkspaceManagersScope` before reading the selection. Every outcome is reported in a snackbar rather than failing silently.

Prior to this change the button sent a hardcoded placeholder element (`top:cell`, display name `top`) regardless of what was selected — peers received a reference to an element that generally did not exist. Re-verify this section explicitly on the next release.

**Setup.** Launch NetCrux with `cxpServerEnabled = true`, open a design, and start a peer (e.g. WaveCrux) that subscribes to `notify_selection`.

**Steps.**

1. With a design open and **nothing** selected, open the cross-probe panel and press **Send selection** on the peer row. Expected: a snackbar reading "Select an element in the schematic first."; the peer receives nothing.
2. Select a cell in the schematic, then press **Send selection**. Expected: a snackbar reading "Selection sent to <peer>"; the peer receives one `notify_selection` whose element path is the canonical path of the selected cell (`top.u_cpu:cell` shape — the same string Copy Path puts on the clipboard), kind `instance`, display name equal to the cell id, and `netcrux.scope_path` metadata naming the active scope.
3. Select a wire and repeat. Expected: element kind `net`, display name `net_<netId>`.
4. Switch to a second tab with a different design and selection, then press **Send selection** again. Expected: the *second* tab's selection goes on the wire — the panel follows the active tab, not the tab that was active when the dialog opened.
5. Disable the CXP server in Settings → CXP Cross-Probe, reopen the panel, press **Send selection**. Expected: a snackbar reading "The cross-probe server is not running."; nothing is transmitted.
6. Quit the peer, then press **Send selection** before the peer list refreshes. Expected: a snackbar reading "<peer> is no longer connected."

**Edge cases.** No design loaded (no top module / no selected scope) reports the same "select an element first" message as an empty selection — both mean "nothing resolvable". Multi-select transmits only the primary (most recently clicked) element, matching the automatic emitter.

**Automation status.** `[Coverage: UNIT_TEST]` — `test/features/remote/widgets/cross_probe_panel_test.dart` mounts the panel inside a real `WorkspaceManagersScope` with an open tab and asserts the real selection (not a placeholder) reaches the wire, plus the wire-kind mapping and all four outcome snackbars. `test/services/remote/cxp/cxp_selection_resolver_test.dart` pins the canonical-path / kind / display-name mapping. Steps 4 and 6 (live tab switch, peer disappearing mid-flight against a real socket) stay `[Coverage: MANUAL]`.

### 6.5.2 Cross-probe panel — unreachable-peer indicator

**What it does.** The panel renders a persistent warning row per peer that was **discovered but could not be dialed** — one-way connectivity, where a peer's manifest is present in the shared directory yet its CXP server never accepts the connector's socket (its process is starting, crashed without removing its manifest, is firewalled, or bound a port the connector cannot reach). Each row shows a warning icon and "Couldn't reach <peer>" (the peer id). The rows are sourced from `cxpDialFailuresProvider`, which snapshots `CxpPeerConnector.lastDialFailures` (exposed through `NetcruxCxpServer.dialFailures` / `unreachablePeers`) and re-emits on every dial failure, discovery add/remove, and inbound presence event. When every discovered peer is reachable the section renders nothing, so it stays unobtrusive in the common case.

Before this indicator, `CxpPeerConnector.dialFailures` was consumed nowhere: an unreachable peer was indistinguishable from an absent one, and a peer we could see but never reach left no on-screen trace.

**Setup.** Launch NetCrux with `cxpServerEnabled = true`. Create a stale/unreachable peer manifest in the shared `crux/cxp/peers/` directory — e.g. copy a real peer's `<peer>.json` and point its `port` at a closed port, or start a peer, let NetCrux discover it, then hard-kill the peer so its manifest lingers past the connector's dial retries.

**Steps.**

1. With the unreachable manifest present, open the cross-probe panel. Expected: within one retry interval (~5 s) a warning row "Couldn't reach <peer>" appears below the Peers list; the icon is the error-colored warning triangle.
2. Make the peer reachable (start its server on the manifest's port, or with the hard-killed peer, relaunch it). Expected: on the next successful handshake the warning row disappears (the peer moves into the connected Peers list).
3. Remove the stale manifest from the directory. Expected: the warning row disappears within ~2 s (discovery removal clears the failure entry).
4. With every discovered peer reachable, confirm no warning row and no warning icon renders.

**Edge cases.** Multiple unreachable peers render one row each. A peer that is *both* unreachable now and was connected before shows only the warning row once the connector's link drops and re-dials fail. The indicator reflects the connector's per-peer failure map, so a peer that recovers on a background retry (no discovery/presence event) still clears on the next connector signal.

**Automation status.** `[Coverage: UNIT_TEST]` — `test/features/remote/providers/cxp_dial_failures_provider_test.dart` drives the provider through the empty-server path, the discovery-degraded (no stream) path, a dial failure producing a snapshot, and a fresh re-read after recovery (proving the provider re-reads the map rather than accumulating). `test/features/remote/widgets/cross_probe_panel_test.dart` asserts the warning row + icon render on a dial failure and are absent when the failure list is empty. `test/services/remote/cxp/netcrux_cxp_server_test.dart` pins the server getters (null/empty before start, live after, back to null on stop). Steps 1–3 against a real lingering manifest and a live recovery stay `[Coverage: MANUAL]`.

### 6.5.3 Cross-probe panel: the send button's PRO badge

**What it does.** Each peer row's **Send selection to this peer** button carries the suite's feature-tier chip (`NetCruxFeatureTierBadge`, reading **PRO**) on its leading side, so the tier is visible before the press, as on every other gated control (crux-shared#8). The chip comes from the shared panel's optional `sendBadgeBuilder` seam (`crux_cxp_ui`), which `NetCruxCrossProbePanel` fills with `kCrossProbeOriginateRequiredTier`, the same constant `crossProbeOriginateGateProvider` enforces. The chip names what the feature needs, not what the seat holds, so it shows at every tier and during the beta. It labels the button and does not gate it: the gate still runs on the press.

**Setup.** Launch NetCrux with `cxpServerEnabled = true`, open a design, and start a peer (e.g. WaveCrux) so one peer row is listed.

**Steps.**

1. Open the Cross-Probe panel at Open Core (a release build with no licence, or `--dart-define=LICENSE_TIER=openCore`). Expected: the peer row shows a **PRO** chip immediately left of the send icon, before anything is pressed.
2. Press the send button. Expected: the upgrade dialog opens naming Pro; the peer receives nothing.
3. Relaunch with `--dart-define=LICENSE_TIER=pro` and open the panel. Expected: the **PRO** chip is still shown, and a press with a cell selected reaches the peer.
4. Switch the app to light and dark themes, and to each of the five locales. Expected: the chip stays legible and its label is the locale's `tierBadgePro` string; a screen reader announces the chip's Pro semantic label beside the button's tooltip.

**Automation status.** `[Coverage: UNIT_TEST]`: `test/features/remote/widgets/cross_probe_panel_test.dart` asserts the chip renders before any press at post-beta Open Core with the gate's required tier and leads the button, and still renders at Pro and during the beta. `crux-shared/packages/crux_cxp_ui/test/cross_probe_panel_test.dart` pins the seam itself (no badge without a builder, a null per-row answer leaves that row bare, the badge never blocks the send). Step 4 stays `[Coverage: MANUAL]`.

### 6.6 Locale sweep

The cross-probe panel and the Settings → CXP Cross-Probe section render in all five locales (en, zh_CN, zh, ja, ko). Automated via the locale-sweep test in `test/features/remote/widgets/cross_probe_panel_test.dart`.

## 7. Pro extension-point seams (Open Core)

Pro features land in the Pro overlay against extension-point seams defined here in open-core. Each seam needs an entry covering: (a) the open-core default behaves correctly with no Pro overlay loaded; (b) the seam is overridable by a Pro implementation; (c) the dispatch path falls back cleanly when the Pro overlay is not present.

### 7.1 Cone-of-influence extension point — `ConeOfInfluenceService`

**What it does.** Defines the abstract `ConeOfInfluenceService` interface in `lib/domain/interfaces/cone_of_influence_service.dart`, the `coneOfInfluenceServiceProvider` Riverpod provider in `lib/services/schematic/cone_of_influence_service_provider.dart`, and the open-core `NoopConeOfInfluenceService` default. The Pro overlay's `proOverrides` list replaces the default with a concrete `ProConeOfInfluenceService` that performs depth-bounded BFS over the laid-out graph. The workspace screen's action dispatcher invokes the service for `NetcruxAction.showConeOfInfluenceFanin` / `showConeOfInfluenceFanout` and writes the resulting overlay into the active tab's `traceOverlayProvider`.

**Setup.** Open any project in the open-core build (no Pro overlay). Pick a cell in the schematic so a selection exists.

**Steps and expected behavior.**
1. Open the command palette (Ctrl/Cmd+Shift+P) and search for "Cone of Influence". Three actions appear: "Show Cone of Influence (Fanin)", "Show Cone of Influence (Fanout)", "Clear Cone of Influence" (labels per the active locale).
2. Activate "Show Cone of Influence (Fanin)". The dispatch path runs but the open-core `NoopConeOfInfluenceService` returns an empty overlay → no visual change, no error, the canvas paints normally.
3. Activate "Clear Cone of Influence". The trace overlay is cleared (idempotent if already clear).

**Tier-gate scenarios.**
- The workspace dispatcher gates these Pro actions through `allowProAction` (via the dispatcher's `_proActionAllowed`), which reads the overridable `betaPeriodProvider` + `licenseTierProvider` (not the compile-time `kBetaPeriod` constant), so both paths below are exercised at runtime by `test/features/workspace/screens/workspace_screen_gating_test.dart`.
- `betaPeriodProvider = true` (beta, current default): the gate short-circuits to admit regardless of tier — the dispatch reaches the no-op service and quietly produces no overlay (correct behavior for open-core).
- `betaPeriodProvider = false` (post-beta), current tier `openCore`: `allowProAction` returns false and the dispatch returns early before calling the service (license gate denies). Same observable result (empty overlay), but for a different reason. A tier whose `featureEquivalent` satisfies Pro (Pro / EDU / Enterprise) admits.

**Edge cases.**
- Empty selection: dispatch returns early before reading the laid-out graph.
- No active tab / empty graph: dispatch returns early.
- Override registration: a `ProviderContainer` with `coneOfInfluenceServiceProvider.overrideWith((_) => fakeService)` resolves to the fake — covered by `test/services/schematic/cone_of_influence_service_provider_test.dart`.

**Automation assessment.** Unit-testable: `NoopConeOfInfluenceService.compute` returns `TraceOverlay.empty` for any input (`test/domain/interfaces/cone_of_influence_service_test.dart`); provider override semantics covered in `test/services/schematic/cone_of_influence_service_provider_test.dart`. Action dispatch wiring is covered indirectly through the action-id / category / required-tier conformance tests (`test/core/shortcuts/netcrux_action_test.dart`). `[Coverage: INTEGRATION_TEST]` — `integration_test/schematic/cone_of_influence_seam_test.dart` boots the real app, seeds a design (Yosys-free), asserts `coneOfInfluenceServiceProvider` resolves to `NoopConeOfInfluenceService`, and dispatches both `compute` and `computeAsync` against a real laid-out graph + selection, asserting `TraceOverlay.empty`. Manual verification: confirm the three actions appear in the command palette in all five locales and the no-op path produces no visible change.

### 7.2 NetcruxAction `requiredTier` extension + action-surface tier badges

**What it does.** Adds `NetcruxActionRequiredTier.requiredTier` (open-core) returning `LicenseTier.openCore` / `LicenseTier.pro` / `LicenseTier.enterprise` per action, and renders that tier on the two action-discovery surfaces per the CLAUDE.md rule:

- **Command palette** — `CommandPaletteDialog` passes a `trailingBuilder` to the cross-suite `CommandPalette` (the `crux_command_palette` package already ships the slot — the earlier "needs a `trailingFor` follow-up" note was stale, corrected 2026-07-16) that renders a `NetCruxFeatureTierBadge(requiredTier: action.requiredTier)` to the right of each Pro/Enterprise row and `null` for open-core rows.
- **Native menu bar** — `DesktopMenuBar` can only emit string labels (no badge widget), so it appends a localized parenthetical suffix via `tierLabelSuffix(action.requiredTier, l10n)` — `" (PRO)"` / `" (ENT)"`, empty for open-core / edu. Suffix text uses the `menuItemTierSuffix` + `tierBadgePro` / `tierBadgeEnterprise` ARB keys (5 locales).

Both surfaces read the single `requiredTier` source of truth; adding a Pro action badges it on both automatically.

**Steps and expected behavior.**
1. Open the command palette and type "Show Cone of Influence (Fanin)". The row renders a `PRO` chip to the right of its label; the shortcut hint (if bound) renders after it.
2. Type "Open Project". The row renders **no** chip (open-core action).
3. Open the native menu bar. The **View → Show Cone of Influence (Fanin)** item reads `Show Cone of Influence (Fanin) (PRO)`; **File → Open Project…** has no suffix. On macOS the suffix appears in the system menu bar; on Windows / Linux in the in-window menu bar.
4. Read `NetcruxAction.showConeOfInfluenceFanin.requiredTier`; expect `LicenseTier.pro`. Read `NetcruxAction.clearConeOfInfluence.requiredTier`; expect `LicenseTier.openCore` (clearing is always available). Show Bookmarks Panel and Show Annotations Panel are Pro — only the overlay provides the panels.
5. In an open-core build (no Pro overlay) during the beta, choose any Pro action — from the palette, the menu, or the inspector's **Go to source** (which carries a `PRO` badge). Expected: a "<action> requires NetCrux Pro." snackbar and nothing else; never silence. Post-beta at the open-core tier the upgrade dialog shows instead. With the Pro overlay installed (`proOverlayInstalledProvider` overridden to true), the action runs.

**Automation assessment.** The gate's four outcomes (open-core action; Pro action without overlay; with overlay; post-beta insufficient tier) in `test/features/workspace/services/pro_action_gate_test.dart`; every opener-backed Pro action explaining itself without the overlay in `test/features/workspace/screens/workspace_screen_gating_test.dart`; the inspector button's badge and gate in `test/features/inspector/widgets/inspector_panel_test.dart`. `requiredTier` mapping fully unit-tested in `test/core/shortcuts/netcrux_action_test.dart` (`NetcruxActionRequiredTier` group). `tierLabelSuffix` unit-tested across all 5 locales in `test/core/shortcuts/action_tier_label_test.dart`. Palette badge (present for a Pro action, absent for a free action, 5-locale sweep) in `test/features/command_palette/widgets/command_palette_dialog_test.dart`. Menu-bar suffix (present for a Pro action, absent for a free action, macOS + Windows + Linux, 5-locale sweep) in `test/features/menu_bar/widgets/desktop_menu_bar_test.dart`.

### 7.4 X-trace extension point — `XTraceService`

**What it does.** Defines the abstract `XTraceService` interface in `lib/domain/interfaces/x_trace_service.dart`, the `xTraceServiceProvider` Riverpod provider in `lib/services/schematic/x_trace_service_provider.dart`, the open-core `NoopXTraceService` default, and the per-tab `xTraceResultProvider` notifier in `lib/features/viewer/providers/x_trace_result_notifier.dart` for surfacing results into the UI. The Pro overlay's `proOverrides` list replaces the default with a concrete `ProXTraceService` that walks backward through the driving cone of the selected net. The workspace screen's action dispatcher invokes the service for `NetcruxAction.showXTrace`, surfaces the result into the per-tab `xTraceResultProvider`, and the `NetcruxAction.clearXTrace` action wipes it.

**Discoverability.** `showXTrace` and `showXTracePanel` declare the `menu` + `palette` surfaces in the action descriptor table (`lib/core/shortcuts/netcrux_action_descriptors.dart`), and the result renders in `XTraceResultPanel`, which opens on its empty state under the no-op service. `clearXTrace` stays visible (clearing is never gated).

**Setup.** Open any project in the open-core build (no Pro overlay). Select a wire / net so a selection exists.

**Steps and expected behavior.**
1. Open the command palette (Ctrl/Cmd+Shift+P) and search for "X-Trace". "Show X-Trace", "Show X-Trace Panel" and "Clear X-Trace" appear (labels per the active locale), "Show X-Trace" with its Pro badge. The same holds for the menu bar.
2. Activate "Show X-Trace" (or a user-assigned keyboard binding — the action is bindable in Settings → Shortcuts). The dispatch path runs but the open-core `NoopXTraceService` returns `XTraceResult.empty` → `xTraceResultProvider` stays in its empty state, no error.
3. Activate "Clear X-Trace". The result is cleared (idempotent if already clear).

**Tier-gate scenarios.**
- The workspace dispatcher gates this Pro action through `allowProAction` (via the dispatcher's `_proActionAllowed`), which reads the overridable `betaPeriodProvider` + `licenseTierProvider` (not the compile-time `kBetaPeriod` constant); both paths below are exercised at runtime by `test/features/workspace/screens/workspace_screen_gating_test.dart`.
- `betaPeriodProvider = true` (beta, current default): the gate short-circuits to admit regardless of tier — the dispatch reaches the no-op service and quietly produces an empty result (correct behavior for open-core).
- `betaPeriodProvider = false` (post-beta), current tier `openCore`: `allowProAction` returns false and the dispatch returns early before calling the service (license gate denies). Same observable result. A tier whose `featureEquivalent` satisfies Pro (Pro / EDU / Enterprise) admits.

**Edge cases.**
- Empty selection: dispatch returns early before reading the laid-out graph.
- No active tab / empty graph: dispatch returns early.
- Override registration: a `ProviderContainer` with `xTraceServiceProvider.overrideWith((_) => fakeService)` resolves to the fake — covered by `test/services/schematic/x_trace_service_provider_test.dart`.

**Automation assessment.** Unit-testable: `NoopXTraceService.trace` returns `XTraceResult.empty` for any input (`test/domain/interfaces/x_trace_service_test.dart`); provider override semantics covered in `test/services/schematic/x_trace_service_provider_test.dart`; `XTraceResultNotifier` state transitions covered in `test/features/viewer/providers/x_trace_result_notifier_test.dart`. Action conformance covered in `test/core/shortcuts/netcrux_action_test.dart`. `[Coverage: INTEGRATION_TEST]` — `integration_test/schematic/x_trace_seam_test.dart` boots the real app, seeds a design (Yosys-free), asserts `xTraceServiceProvider` resolves to `NoopXTraceService`, and dispatches both `trace` and `traceAsync` against a real laid-out graph + selection, asserting `XTraceResult.empty`. Manual verification: confirm the three actions appear in the command palette in all five locales and the no-op path produces no result.

### 7.6 Schematic context-menu extension seam

**What it does.** Adds `SchematicContextMenuExtensionEntry`, `SchematicContextMenuExtensionBuilder`, and the `schematicContextMenuExtensionsProvider` in `lib/features/viewer/widgets/schematic_context_menu_extension.dart`. Modifies the `SchematicContextMenuController.showAt` flow to read the builder list, run each builder against the right-clicked target, and render the returned entries below a divider after the built-in items. The Pro overlay registers a builder via `proOverrides` to inject the "Cross-probe to peer →" entries. Open-core resolves the provider to an empty list — the menu renders only the built-in entries.

**Setup.** Right-click any cell / port / wire / boundary port in the open-core build.

**Steps and expected behavior.**
1. The context menu shows the existing five built-in entries (Copy Path / Trace Fanin / Trace Fanout / Find in Hierarchy / Open in Inspector). No additional entries below — the provider returns empty.
2. Selecting any built-in entry dispatches as before; no regressions in the existing flow.
3. Overriding `schematicContextMenuExtensionsProvider` with a builder that emits one entry → the menu renders the entry below a `PopupMenuDivider`. Selecting the entry calls its `onTap` closure with the build context + ref.
4. Entries with `enabled: false` render greyed; entries with a tooltip render their tooltip on hover (desktop) — useful for "Cross-probe to peer → (no peers connected)" disabled state.

**Tier-gate scenarios.**

- Provider is open-core; no tier-gating at this layer. The Pro overlay's contributed entries themselves can be tier-gated by their `onTap` callback (e.g. consult `FeatureGate.isAvailable` before sending the CXP message).

**Edge cases.**

- Builder returns empty list for a given target → no entry is appended for that target (the divider only renders when at least one extension entry is present).
- Multiple builders registered → entries from each builder are concatenated in registration order. No de-duplication; contributors are responsible for unique ids.

**Automation assessment.** Provider default + override semantics covered by `test/features/viewer/widgets/schematic_context_menu_extension_test.dart`. The controller's showMenu integration is implicitly verified at runtime; a widget-test capturing the menu items list under override is a follow-up.

### 7.5 Bookmarks + Annotations seam — `BookmarkAnnotationStore`

**What it does.** Defines the abstract `BookmarkAnnotationStore` interface in `lib/domain/interfaces/bookmark_annotation_store.dart`, the `bookmarkAnnotationStoreProvider` / `bookmarkAnnotationSnapshotProvider` in `lib/services/session/`, the open-core `NoopBookmarkAnnotationStore` default, and the `Bookmark` / `Annotation` domain models. Extends `NetcruxSession` with optional `bookmarks` + `annotations` fields so the Pro overlay's `InSessionBookmarkAnnotationStore` can round-trip data through the `.netcrux` session file. Adds four `NetcruxAction` values (`addBookmark`, `showBookmarksPanel`, `addAnnotation`, `showAnnotationsPanel`) with `requiredTier` mapping (`addBookmark` / `addAnnotation` → Pro; panel-toggle actions stay Open Core).

**Setup.** Open the open-core build (no Pro overlay). Confirm `bookmarkAnnotationStoreProvider` resolves to a `NoopBookmarkAnnotationStore` and the snapshot is empty.

**Steps and expected behavior.**
1. Open the command palette (Ctrl/Cmd+Shift+P) and search for "Bookmark" / "Annotation". Four actions appear under the Tools category. They are dispatched but no-op in open-core (the workspace screen's switch falls through to `break`).
2. Save a session via `Save Session…` — the JSON does not contain `bookmarks` / `annotations` keys when both lists are empty (readable by builds that predate bookmarks).
3. Load a `.netcrux` session that *does* carry bookmarks + annotations — open-core silently ignores the writes (the no-op store is a sink) but the JSON parses without error.
4. The `Bookmark` and `Annotation` domain models round-trip every `BookmarkTargetKind` value through JSON unchanged.

**Tier-gate scenarios.**
- The `addBookmark` / `addAnnotation` dispatch routes through the open-core opener seam (`addBookmarkDialogOpenerProvider` / `addAnnotationDialogOpenerProvider`, no-op default), gated by `allowProAction` (via the dispatcher's `_proActionAllowed`) which reads the overridable `betaPeriodProvider` + `licenseTierProvider`. Both paths are exercised at runtime by `test/features/workspace/screens/workspace_screen_gating_test.dart`.
- `betaPeriodProvider = true` (beta): the gate admits regardless of tier — the Pro overlay's opener reaches the live store; the open-core opener is a no-op (the dialog widgets only exist in Pro), so nothing renders on open-core.
- `betaPeriodProvider = false` (post-beta), current tier `openCore`: `allowProAction` returns false and the dispatch returns before calling the opener. The Pro feature is wholly Pro — there is no open-core surface to render either way.

**Edge cases.**
- Sessions from builds that predate bookmarks, with no `bookmarks` / `annotations` keys load cleanly; the fields default to empty lists.
- Malformed bookmark / annotation entries in a session file are silently dropped (`Bookmark.fromJson` / `Annotation.fromJson` return `null`); the rest of the session loads correctly.
- Unknown `targetKind` strings are treated the same way — forward-compatible with future kind additions.
- Override registration: a `ProviderContainer` with `bookmarkAnnotationStoreProvider.overrideWith((_) => fakeStore)` resolves to the fake — covered by `test/services/session/bookmark_annotation_store_provider_test.dart`.

**Automation assessment.** Domain-model round-trip + equality covered by `test/domain/models/bookmark_test.dart` + `test/domain/models/annotation_test.dart`. Session round-trip with mixed valid + malformed entries covered by `test/domain/models/session/netcrux_session_test.dart`. NoopStore no-op semantics covered by `test/domain/interfaces/bookmark_annotation_store_test.dart`. Provider override semantics covered by `test/services/session/bookmark_annotation_store_provider_test.dart`. Action conformance covered in `test/core/shortcuts/netcrux_action_test.dart`. `[Coverage: INTEGRATION_TEST]` — `integration_test/session/bookmark_annotation_seam_test.dart` boots the real app, seeds a design (Yosys-free), asserts `bookmarkAnnotationStoreProvider` resolves to `NoopBookmarkAnnotationStore`, and dispatches every read/write against a bookmark/annotation targeting a real seeded cell, asserting the snapshot stays `BookmarkAnnotationSnapshot.empty`. Manual verification: confirm the four actions appear in the command palette in all five locales.

### 7.3 NetcruxLicenseBadgeStrings adapter + NetCruxFeatureTierBadge / NetcruxEducationalBadge wrappers

**What it does.** Bridges the cross-suite `package:crux_license` `FeatureTierBadge` and `EditionBadge` widgets to the open-core ARB-backed `L10N` class. `NetcruxLicenseBadgeStrings(l10n)` implements `LicenseBadgeStrings`; the `NetCruxFeatureTierBadge` / `NetcruxEducationalBadge` wrappers in `lib/shared/widgets/` construct the adapter from `BuildContext` so callers don't have to.

**Steps and expected behavior.**
1. Render `NetCruxFeatureTierBadge(requiredTier: LicenseTier.pro)` inside a `MaterialApp` with locale `en`. Expect the chip text `PRO`. Repeat for zh_CN, zh, ja, ko — chip text is `PRO` everywhere (label is intentionally untranslated) but the screen-reader semantic phrase is localized (Pro 等级功能 / Pro ティア機能 / Pro 등급 기능).
2. `NetCruxFeatureTierBadge(requiredTier: LicenseTier.openCore)` / `LicenseTier.edu` collapses to `SizedBox.shrink` (no chip).
3. `NetcruxEducationalBadge(tier: LicenseTier.edu)` renders the localized EDU chip. All other tiers collapse to `SizedBox.shrink`.

**Automation assessment.** Locale sweep tests in `test/shared/widgets/netcrux_{tier,educational}_badge_test.dart` and `test/core/license/netcrux_license_badge_strings_test.dart`.

### 7.7 Custom cell symbols seam — `CustomCellSymbolRegistry` + `CellBodyPainterFactory`

**What it does.** Defines the abstract `CustomCellSymbolRegistry` interface in `lib/domain/interfaces/custom_cell_symbol_registry.dart`, the `customCellSymbolRegistryProvider` / `customCellSymbolSnapshotProvider` in `lib/services/custom_cell_symbols/`, the open-core `NoopCustomCellSymbolRegistry` default, and the renderer-side `CellBodyPainterFactory` typedef + `cellBodyPainterFactoryProvider` in `lib/features/viewer/symbols/`. Adds the `CustomCellSymbol` / `PortAnchor` / `CustomCellSymbolMatch` value types plus four `NetcruxAction` values (`openSymbolManager`, `importSymbolFromSvg`, `editSymbolForCurrentInstance`, `removeSymbolForCurrentInstance`) with the matching opener seams in `lib/services/custom_cell_symbols/custom_cell_symbol_openers.dart`. The Pro overlay's `proOverrides` replaces the registry default with a `ProCustomCellSymbolRegistry` (per-project + per-user disk storage) and the factory default with one that consults the registry snapshot to return SVG-rendering painters.

**Setup.** Open the open-core build (no Pro overlay). Open any project so a schematic is rendered.

**Steps and expected behavior.**
1. Open the command palette and search for "Symbol". Four actions appear under the Tools category: "Open Custom Cell Symbol Manager…", "Import Symbol from SVG…", "Edit Symbol for This Module…", "Remove Custom Symbol for This Module" (labels per the active locale). Each is dispatched through the no-op opener provider and produces no UI change in open-core.
2. The schematic continues to render every cell with its built-in `painterFor(cell.kind)`. The `customCellSymbolSnapshotProvider` resolves to the empty map; `cellBodyPainterFactoryProvider` resolves to `defaultCellBodyPainterFactory`, which returns `painterFor(cell.kind)` for every cell.
3. Save a session — no `customCellSymbols` key appears in the JSON (the no-op registry has no on-disk state to round-trip).

**Tier-gate scenarios.**
- The workspace dispatcher gates these Pro actions through `allowProAction` (via the dispatcher's `_proActionAllowed`), which reads the overridable `betaPeriodProvider` + `licenseTierProvider` (not the compile-time `kBetaPeriod` constant); both paths below are exercised at runtime by `test/features/workspace/screens/workspace_screen_gating_test.dart`.
- `betaPeriodProvider = true` (beta, current default): the gate short-circuits to admit regardless of tier — the dispatch reaches the no-op openers and quietly does nothing.
- `betaPeriodProvider = false` (post-beta), current tier `openCore`: `allowProAction` returns false and the dispatch returns early before calling the opener (license gate denies). Same observable result. A tier whose `featureEquivalent` satisfies Pro (Pro / EDU / Enterprise) admits.

**Edge cases.**
- Overriding `customCellSymbolRegistryProvider` with a fake that emits via `changed` → `customCellSymbolSnapshotProvider` re-emits a fresh map; the schematic canvas repaints. Covered by `test/services/custom_cell_symbols/custom_cell_symbol_registry_provider_test.dart`.
- Overriding `cellBodyPainterFactoryProvider` with a fake factory that returns a custom painter for `cell.type == 'my_alu'` → the schematic uses the custom painter for matching cells and falls back to the default for others. Covered by `test/features/viewer/symbols/cell_body_painter_factory_test.dart`.
- `CustomCellSymbol.fromJson` tolerates missing optional fields, unknown enum values, and malformed port-anchor entries — covered in `test/domain/models/custom_cell_symbol/`.

**Automation assessment.** Domain-model round-trip + equality covered by `test/domain/models/custom_cell_symbol/{port_anchor,custom_cell_symbol,custom_cell_symbol_match}_test.dart`. NoopRegistry no-op semantics covered by `test/domain/interfaces/custom_cell_symbol_registry_test.dart`. Provider default + override semantics covered by `test/services/custom_cell_symbols/custom_cell_symbol_registry_provider_test.dart` and `test/services/custom_cell_symbols/custom_cell_symbol_openers_test.dart`. Renderer factory default + override covered by `test/features/viewer/symbols/cell_body_painter_factory_test.dart`. Action conformance covered in `test/core/shortcuts/netcrux_action_test.dart`. `[Coverage: INTEGRATION_TEST]` — `integration_test/custom_cell_symbols/custom_cell_symbol_seam_test.dart` boots the real app, seeds a design (Yosys-free), asserts `customCellSymbolRegistryProvider` resolves to `NoopCustomCellSymbolRegistry`, and dispatches `lookup` / `listAll` / `addOrUpdate` / `remove` against a real seeded module type (`cpu`), asserting empty results and a `changed` stream that never emits. Manual verification: confirm the four actions appear in the command palette in all five locales and the no-op path produces no visible change in the schematic.

## 8. Color Theming & Customization (suite-wide)

NetCrux adopts `crux_theme`'s preset-driven theming the same way WaveCrux does: `cruxColorThemeProvider` holds the active `CruxColorTheme`, a `NetcruxCruxColorThemeNotifier` override bridges between `AppSettings.core.activeThemeName` / `themeOverrides` and that provider, and the root `MaterialApp` runs every base theme through `applyChromeTokens(...)` while driving `themeMode` via `themeModeFromBrightness(...)`. End-users see the same Settings → Appearance section across the four-app suite.

### What it does

- **Preset picker** — four built-in presets rendered as `PresetCard`s (`wavecrux-dark`, `wavecrux-light`, `solarized-dark`, `high-contrast-dark`, `oscilloscope`). Tapping a preset writes through to `AppSettings.core.activeThemeName` and triggers a Material rebuild.
- **Brightness toggle** — `MaterialApp.themeMode` follows the active preset's `brightness`. Picking a light preset flips the whole chrome to light immediately; picking dark/Solarized/Oscilloscope flips it back.
- **Chrome tokens** — presets that ship `chrome.*` tokens (Solarized Dark, Oscilloscope) re-tint the scaffold, AppBar, panel surfaces, and card surfaces via `applyChromeTokens`. Presets without chrome tokens (WaveCrux Dark/Light, High Contrast Dark) keep the tuned `NetcruxTheme` defaults.
- **Per-token editor** — `TokenCategorySection` exposes every registered chrome token for direct color editing through `ColorPickerDialog`.
- **Theme packs** — install / activate / uninstall flow for `.crux-theme.json` files (same format as the other suite apps; chrome-only packs are valid).
- **Locale** — every preset card, token row, color picker, and pack-browser string flows through `crux_theme`'s `ThemeAppearanceStrings`.

### Setup

- Open a schematic so the workspace chrome is fully populated.
- Open Settings → Appearance.

### Step-by-step verification

#### 8.1 Preset switching repaints every surface

1. Tap `WaveCrux Light`. **Expected:**
   - Settings dialog background flips to light immediately.
   - Behind the dialog, the workspace AppBar, hierarchy panel, status bar, schematic background all flip to light.
2. Tap `Solarized Dark`. **Expected:**
   - Chrome surfaces re-tint with Solarized hues (teal-blue), NOT default Material-3 dark.
   - Schematic canvas background follows.
3. Tap `Oscilloscope`. **Expected:**
   - Chrome flips to phosphor-green-on-black.
4. Quit the app and relaunch. **Expected:** whichever preset you left active is restored — chrome included.

#### 8.2 Per-token chrome override

1. Expand the **Chrome** category in the Color overrides section.
2. Tap `toolbar.background`'s swatch. Pick a contrasting color. **Expected:** the toolbar background changes immediately; the reset button next to the swatch becomes enabled.
3. Tap reset. **Expected:** the toolbar reverts to the active preset's chrome (or the `NetcruxTheme` default if the preset doesn't ship that token).
4. Activate a different preset. **Expected:** the override is removed from `AppSettings.core.themeOverrides` only for tokens the new preset overrides; tokens the new preset doesn't touch keep their custom value.

#### 8.3 Theme pack import / export

Follows the same flow as WaveCrux's `22.7.3` / `22.7.4` — only difference is the default export filename: `netcrux-theme.crux-theme.json`.

#### 8.4 Locale sweep

Switch the active locale via Settings → Application → Language to each of `en`, `zh_CN`, `ja`, `ko` and reopen Settings → Appearance. **Expected:** preset names, "Presets" heading, "Color overrides" heading, "Theme packs" heading, and the color picker dialog all render in the active locale. No raw `key.name` strings, no overflow.

### Edge cases

| Scenario | Expected behavior |
|---|---|
| `AppSettings.core.activeThemeName` is unknown at boot | Falls back to `wavecrux-dark`; UI does not crash |
| Imported pack has an unknown chrome token id | Pack installs; unknown token is silently ignored |
| Imported pack omits the `chrome` key entirely | Pack installs; chrome surfaces use `NetcruxTheme` defaults |
| File picker cancelled | No change |

### Automation assessment

| Test | Coverage | Assessment |
|---|---|---|
| `CruxColorTheme` model / `ThemePackCodec` / `ThemePackService` (package) | `crux_theme` package suite | **AUTOMATED** (upstream) |
| `applyChromeTokens` / `themeModeFromBrightness` (package) | `crux_theme/test/chrome_theme_data_test.dart` | **AUTOMATED** |
| `NetcruxCruxColorThemeNotifier.activate` persists to settings | Pending — add to `test/core/theme/` | **HYBRID** |
| Brightness toggle from preset selection | **INTEGRATION_TEST** (`integration_test/theme/theme_switch_test.dart` — switching the active preset flips the live `MaterialApp.themeMode` dark↔light end-to-end through the `appSettingsProvider` → `cruxColorThemeProvider` bridge) + **MANUAL** for the actual on-screen repaint of every chrome surface |
| Chrome token override visible in toolbar / status bar | **MANUAL** — visual verification |
| Locale sweep on Settings → Appearance | Pending — `test/features/settings/widgets/color_theme_section_test.dart` | **AUTOMATED** when added |

---

## 9. Robustness & Performance — Yosys subprocess + malformed-input hardening

The open-core half of the robustness and performance work: bounded elaboration, malformed-input hardening, the fixture ladder, the perf harness, and CXP degradation. The Pro overlay's own guide covers its half.

### 9.1 Bounded, killable Yosys elaboration (the seam)

**What it does.** A hung Yosys can no longer block the elaboration future forever. The subprocess seam lives in `crux_yosys` (`crux-shared`): `ProcessRunner.run` / `YosysRunner.run` spawn via `Process.start` and accept `timeout` / `cancelSignal`; on overrun the process is `SIGKILL`'d (`ProcessTermination.timedOut` → `YosysRunTimeout`) and on a fired cancel terminated (`cancelled` → `YosysRunCancelled`), both still cleaning up the `write_json` temp file. In `netcrux`, `ElaborationTimeoutPolicy` (`lib/domain/interfaces/`) + `DefaultElaborationTimeoutPolicy` (30 s floor → 10 min cap, scaled by source byte size) feed `loaded_netlist_provider`, which maps a timeout to `YosysTimeoutException` and drops a superseded/tab-closed run to the empty state. The Pro overlay may override `elaborationTimeoutPolicyProvider` for a configurable per-design budget, but is not required — the default closes the gap.

**Diagnostics-assisted verification.** Run `dart test` in `crux-shared/packages/crux_yosys/` — `process_runner_timeout_test.dart` proves a real 30 s sleeper is killed under a 300 ms budget; `yosys_runner_test.dart` asserts the result-type mapping + temp cleanup on kill. Run `flutter test test/services/yosys/` in `netcrux` — `elaboration_timeout_provider_test.dart` (budget math) + `yosys_runner_timeout_test.dart` (pipeline surfaces the typed timeout; cancel → empty).

### 9.2 Open-core malformed-input hardening

- **Yosys-JSON.** `StreamingYosysJsonReader` (the production path) now funnels a nested type error (a cell's `connections` is a string) or a bad module-name escape into a typed `YosysJsonParseException` carrying the module name as the JSON path — previously a raw `TypeError`/`FormatException` leaked. `yosys_json_fuzz_test.dart` sweeps the hand-authored `test/fixtures/netlist/malformed/` corpus (one file per invariant, listed in the corpus README) + seeded truncation / type-mutation / a 100 k-deep array, against both the in-memory and streaming parsers.
- **Workspace codec.** `workspace_codec_fuzz_test.dart` asserts `NetcruxWorkspaceCodec.payloadFromJson` surfaces a typed `FormatException` for every malformed field and never a raw error — the property the corrupt-workspace recovery path (§9.4) relies on.

### 9.3 Large-netlist stress ladder + Yosys-free golden sweep

**What it does.** A committed ladder of deterministic `$_DFF_P_` chain/grid designs (`chain_1k` / `chain_10k` / `grid_100k`; `mesh_1m` built on demand) lets the parser be regression-tested at scale **without spawning Yosys**. `tool/generate_netlist_fixtures.dart` synthesizes the Yosys-shaped JSON (gzip for the large tiers) + a `NetlistGolden` companion (counts + cell-type histogram + FNV-1a fingerprint). `netlist_golden_test.dart` parses each committed design, recomputes the golden, and diffs it against the committed snapshot — a parser regression shows as `cellCount 10000 → 9999`, not an opaque hash.

**Diagnostics-assisted verification.** `flutter test test/services/yosys/netlist_golden_test.dart` (Yosys-free; `chain_10k` asserts exactly 10000 cells). Refresh after a deliberate change: `REGENERATE=1 flutter test …`. Bench: `flutter test --dart-define=RUN_BENCHMARKS=true test/perf/ingest_bench_test.dart` → `build/perf/ingest.jsonl`.

**Captured tier.** `test/fixtures/netlist/picorv32/captured/` holds a real ISC-licensed RV32IMC core elaborated with Yosys 0.66 (1 599 cells, real `$mux`/`$eq`/`$dff` types) + golden + `PROVENANCE.md`; the golden sweep + the `captured_fixture_licenses` / `netlist_fixture_companion` guards now discover the `captured/` tier. The same directory also carries **`picorv32.v` — the genuine RTL source** at the same pinned upstream commit (`87c89acc`), so the design can be **opened and rendered live** in NetCrux (not just parsed as a netlist): elaborating it reproduces the committed 1 599-cell netlist exactly. See §9.9. **Measured baseline:** 1M-cell parse 4.8 s (goal < 30 s ✓); peak RSS ~4.3 GB (goal < 4 GB ⚠ — the eager parse; a streaming SAX reader would close it). Single-machine numbers; software-raster + JIT caveats apply.

### 9.4 Corrupt-workspace quarantine + recovery

**What it does.** A corrupt / truncated / non-object-root / bad-schema `workspace.json` on launch is moved aside to `workspace.json.corrupt-<timestamp>` (preserving the bytes), the app launches into a clean default workspace, and a localized notice is surfaced. Atomic temp+rename write + recover-to-empty live in `crux_workspace`; the quarantine + the `WorkspaceRecovery` signal (`takeRecovery()`) sit on top of them. A transient (non-decode) read error recovers WITHOUT quarantining.

**Manual verification.** Corrupt `{appSupportDir}/workspace.json` (truncate it / write garbage), relaunch: the app comes up empty (not bricked), a `workspace.json.corrupt-*` sibling appears, and the "could not restore your workspace" snackbar shows. `flutter test test/services/workspace/workspace_corruption_recovery_test.dart` + `test/integration/workspace_restore_from_corruption_pipeline_test.dart` cover it automatically (incl. the 5-locale notice).

### 9.5 Corpus + subprocess static guardrails

Four `test/static/` guards make the corpus + bounded-subprocess discipline self-enforcing: `netlist_fixture_layout` (no loose fixtures at a design root), `netlist_fixture_companion` (golden / expected-error companions + non-empty corpus), `captured_fixture_licenses` (PROVENANCE SPDX allow-list for the captured tier), and `no_unbounded_subprocess` (fails if a raw `Process` spawn reappears under `lib/services/yosys/`).

### 9.6 Schematic perf harness + whole-scope render golden

**What it does.** A committed perf-regression harness measures the paint hot path and the layout pipeline, and a whole-scope render golden pins the painter's geometry. `flutter test --dart-define=RUN_BENCHMARKS=true test/benchmarks/schematic_paint_bench_test.dart` records paint frame time (avg/p99) for 500/1000/5000 visible cells; `…/elk_layout_bench_test.dart` records the layout pipeline wall-time over the committed chain scopes. `schematic_painter_golden_test.dart` renders a fixed three-cell design at the LOD detail/mid boundary and diffs it against `goldens/whole_scope_chain3.png` (regenerate with `--update-goldens`).

### 9.7 COI/X-trace isolate-offload seam (open-core half)

**What it does.** `ConeOfInfluenceService` / `XTraceService` gained an async `computeAsync` / `traceAsync` — the isolate-offload seam. Open-core resolves them inline (the Noop default); the Pro overlay offloads large traces off the UI isolate (verified in the Pro overlay's own guide). `coi_scale_test.dart` drives a 100K-cell synthetic graph through the open-core seam + the one-hop `TraceService`, asserting correctness + termination within a generous `Timeout`. The Pro side avoids marshalling-copying the graph to the worker (a zero-copy connectivity projection); the open-core seam needs no change for it.

### 9.8 CXP bind-failure degradation + robustness

**What it does.** `NetcruxCxpServer.start()` degrades a bind failure (taken port / firewall / sandbox) to `isAvailable=false` + an `unavailableReason` instead of throwing on launch; a manifest-dir failure degrades discovery with a warning. Malformed-inbound rejection + stale-manifest pruning live in `crux_cxp`; this section verifies them, including the malformed-known-kind case: `test/services/remote/cxp/cxp_inbound_fuzz_test.dart` sends a syntactically valid envelope of a *recognised* kind (`hello`) whose payload fails to decode (`identity` is a number, not an object) and asserts `ErrorResponse(code: malformed_payload)` comes back rather than the connection dying — `decodeCxpMessage` now runs inside a `try`/`catch` at the server's dispatch point instead of letting a `FormatException` escape the read loop. **Manual:** confirm a NetCrux launched while another process holds the CXP port comes up fully functional with a "cross-probe unavailable" status (no crash). The macOS `network.server` entitlement / non-sandboxed bind smoke stays manual.

### 9.9 Large real-design live open + render (picorv32 + VexRiscv source)

**What it does.** Verifies NetCrux opens, elaborates, and *renders* genuinely large real-world designs — not degenerate generated arrays. Two captured cores:
- **`test/fixtures/netlist/picorv32/captured/picorv32.v`** — the real ISC RV32IMC core (the `picorv32` core is 1 599 cells of real `$mux`/`$eq`/`$dff`/`$pmux`/`$add` logic), effectively **flat**.
- **`test/fixtures/netlist/vexriscv/captured/vexriscv.v`** — the MIT VexRiscv (`Full` config), a genuinely **hierarchical** design: the `VexRiscv` pipeline (~1 463 cells) instantiating `DataCache` (~404) and `InstructionCache` (~115), ~1 980 cells total. It exercises the **hierarchy browser + per-scope layout + multi-scope layout cache** in a way the flat picorv32 doesn't, and is the larger of the two. Its top auto-selects cleanly (the only un-instantiated module), unlike picorv32.

These are distinct from the generated `chain_*`/`grid_*` ladder, which collapses to one wide register at RTL — those stress the **parser/ingestion**; picorv32 + VexRiscv stress the **hierarchy browser + ELK layout + canvas paint** at real scale.

**Setup.** Yosys on PATH (no ghdl plugin needed — Verilog only).

**Steps and expected behavior.**
1. `netcrux test/fixtures/netlist/picorv32/captured/picorv32.v` (or File → Open Source Files…). Expected: elaboration succeeds; the left pane roots the hierarchy (NOT "no top module"). NetCrux's loose-source `hierarchy -check -auto-top` auto-selects **`picorv32_wb`** (the Wishbone SoC wrapper) as top.
2. Expand the hierarchy: `picorv32_wb → picorv32_axi → picorv32 (+ picorv32_axi_adapter)`. Click the **`picorv32`** scope. Expected: the canvas renders the dense ~1 599-cell core schematic; pan/zoom/fit stay responsive.
3. For a single-click dense view, open instead via a `.netcrux-project` pinning `"topModule": "picorv32"` (see the fixture's `PROVENANCE.md`). Expected: opens straight to the 1 599-cell `picorv32` module.

**Large-scope render correctness (the fix).** Opening the dense `picorv32` core stresses two things that were previously broken for any large scope:
1. **Auto fit-to-view.** When a scope's layout loads, the camera fits the whole layout (`ViewportTransformNotifier.fitToBounds`), and the zoom floor was lowered (`minZoom` 0.1 → 0.01) so a ~15 000 × 43 000 px core actually fits. Before, the viewport stayed at the identity transform (zoom 1.0, top-left), so a large scope showed only an un-navigable corner of overlapping labels. The fit is wired by **watching** the laid-out-graph provider in the gesture handler (not `listen` — the handler only mounts once the layout has loaded, so a `listen` would never fire for the already-present value; that was a real regression where the core opened to the corner). Expected: the **whole** core schematic appears fit-to-screen on navigation; `0` (Fit-All) re-fits; pan/zoom explores. Verify by clicking into `picorv32` — the dense block of cells fills the canvas, centered, rather than a sliver in the corner.
2. **Edge explosion guard.** `buildElkInput` skips routing high-fanout global nets (driver×sink > 32 — clock/reset fan out to ~1 600 flops). Routing them point-to-point produced ~21 000 edges and forced ELK to a 13 000 × 63 000 px, ~7 s layout; the cap brings it to ~18 000 edges. Datapath connectivity is preserved; clock/reset are implied (as in any schematic tool).
3. **Large-scope layered knobs.** For scopes over 500 cells, `buildElkInput` adds `elk.layered.thoroughness: 1` (single crossing-min pass) and `elk.layered.cycleBreaking.strategy: DEPTH_FIRST` (cheaper than the default greedy minimal-reversal search, which is costly on a register-heavy netlist's many Q→D feedback loops). Measured on picorv32: the pure elkjs solve dropped ~54 % (4.5 s → ~2 s) with comparable bounds (20 766 × 43 017). Small scopes keep the higher-quality defaults.

**Performance observation.** Watch elaboration→first-paint latency and pan/zoom frame rate on the dense scope. Yosys elaboration is ~0.1 s; the elkjs solve for ~1 600 cells is **~2 s** (~2.8 s end-to-end cold incl. isolate spawn), with the large-scope layered knobs above; **~96 % of that is the layered solve in QuickJS** (parse + input-build + result-parse are ~185 ms combined; rendering is not the bottleneck). The solve runs on a **dedicated background isolate** (`ElkLayoutService` spawns a long-lived worker that owns the flutter_js elkjs runtime; the UI isolate only builds the ELK input + parses the result), so the UI stays responsive — the canvas shows an **indeterminate progress bar + "Laying out the schematic… (N cells)" + elapsed-seconds readout** instead of freezing (elkjs is opaque, so no true percentage). The result is cached two ways: an **in-memory** cache (re-navigating A→B→A is instant in-session) and a **disk-backed** cache (`<appSupport>/layout-cache/<key>.json.gz`, FIFO-pruned to 64 entries) keyed by a stable FNV-1a hash of the ELK input + engine version — so **re-opening a design across app restarts skips the solve entirely** (the first scope paints near-instantly). To verify the disk cache: open picorv32, navigate into `picorv32` (≈2 s solve), quit, relaunch, reopen the same `.v` and navigate in — the core should paint with no multi-second wait (a `layout-cache/*.json.gz` file exists under app-support). Further speedups beyond option-tuning would require getting the layout off interpreted elkjs (a Dart-native layered layout) — measured to be the dominant cost. Compare paint frame time via the perf harness (`schematic_paint_bench_test.dart`, §9.6) if a regression is suspected.

**Isolate-offload notes.** The worker is spawned with `errorsAreFatal: false`: flutter_js emits a benign asynchronous "Binding has not yet been initialized" error in a background isolate (no `WidgetsBinding`) that does NOT affect the layout result (byte-identical to the in-process output) — left fatal, it would tear the worker down mid-flight and hang the layout. A 2-minute timeout backstops a genuinely wedged worker. Tests inject a host (`hostFactory:`) to keep the solve in-process and deterministic; production (no host) takes the isolate path — covered end-to-end by `elk_layout_service_test.dart`'s "isolate offload" group (real flutter_js + the committed elk bundle, warm-reuse asserted).

**Edge cases.** Opening the bare `.v` with no top pin lands on `picorv32_wb` (correct — it's the only un-instantiated module); the `picorv32` core view is one scope down. Re-elaboration with a Yosys newer than 0.66 may shift internal cell selection slightly but must still root + render.

**Automation Assessment.** `[Coverage: UNIT]` for the netlist parse (`netlist_golden_test.dart` — `picorv32`), `[Coverage: STATIC]` for the captured-fixture license/companion/layout guards. The live elaborate→layout→paint render at this scale is `[Coverage: MANUAL]` (needs Yosys + a real window); the §9.6 paint/layout benchmarks cover the painter/layout hot paths at synthetic 500/1000/5000-cell scales.

### Automation Assessment

| Capability | Assessment |
|------------|------------|
| Bounded elaboration — kill a hung subprocess; clean temp on kill | **Strong** — `crux_yosys` `process_runner_timeout_test.dart` + `yosys_runner_test.dart`. `[Coverage: UNIT_TEST]` |
| Bounded elaboration — size-aware budget + pipeline timeout/cancel wiring | **Strong** — netcrux `elaboration_timeout_provider_test.dart` + `yosys_runner_timeout_test.dart`. `[Coverage: UNIT_TEST]` |
| Malformed input — streaming Yosys-JSON reader never leaks a raw error | **Strong** — `yosys_json_fuzz_test.dart`; mutation anchor: removing the `Module.fromJson` funnel reds `nested_type_error`. `[Coverage: FUZZ]` |
| Malformed input — workspace codec only ever throws `FormatException` | **Strong** — `workspace_codec_fuzz_test.dart` (per-field + seeded truncation/mutation). `[Coverage: FUZZ]` |
| Stress ladder — golden sweep catches a parser regression, Yosys-free | **Strong** — `netlist_golden_test.dart`; mutation anchor: dropping a cell reds the golden + the explicit `chain_10k == 10000` assertion. `[Coverage: UNIT]` |
| Stress ladder — ingest parse-time / peak-RSS per tier | **Recorded** — `ingest_bench_test.dart` (RUN_BENCHMARKS-gated; numbers recorded, no hard assertion). `[Coverage: BENCH]` |
| Workspace recovery — corrupt workspace → empty + quarantine + notice | **Strong** — `workspace_corruption_recovery_test.dart` + `workspace_restore_from_corruption_pipeline_test.dart` (4 corruption shapes + 5-locale notice); crux_workspace `workspace_service_test.dart` (quarantine + atomic-orphan). `[Coverage: UNIT_TEST + INTEGRATION]` |
| Static guards — corpus + subprocess discipline self-enforcing | **Strong** — `test/static/` ×4, all five guard mutations verified red. `[Coverage: STATIC]` |
| Perf harness — whole-scope render golden pins paint geometry | **Strong** — `schematic_painter_golden_test.dart`; mutation anchor: nudging `LodBandRouter.midUpper` reds the golden (verified). `[Coverage: UNIT]` |
| Perf harness — paint frame time / ELK layout wall-time | **Recorded** — `schematic_paint_bench_test` + `elk_layout_bench_test` (RUN_BENCHMARKS-gated; numbers recorded; both run from the nightly `perf.yml` workflow, invoked by exact path since a `*_test.dart` directory scan alone would still catch them). `[Coverage: BENCH]` |
| Isolate offload — open-core async seam holds a 100K scope | **Strong** — `coi_scale_test.dart` (Noop seam + one-hop `TraceService` terminate + correct). `[Coverage: UNIT_TEST]` |
| Isolate offload — Pro isolate offload parity + off-thread (Pro overlay guide) | **Strong** — `isolate_coi_service_test.dart` (inline/async parity + over-threshold isolate route). `[Coverage: UNIT_TEST]` |
| CXP robustness — bind failure degrades, never crashes launch | **Strong** — `cxp_bind_failure_test.dart` (port collision → graceful). `[Coverage: UNIT_TEST]` |
| CXP robustness — malformed inbound → error reply, server alive | **Strong** — `cxp_inbound_fuzz_test.dart`; mutation anchor: dropping the crux_cxp unknown-kind check reds the unknown-verb case (verified). `[Coverage: FUZZ]` |
| CXP robustness — stale manifest pruned | **Strong** — `cxp_stale_manifest_test.dart`. `[Coverage: UNIT_TEST]` |
| Isolate offload — Pro zero-copy projection (no graph copy to worker) | **Strong** — `connectivity_projection_test.dart` (topology is a typed-array struct / no geometry; int BFS reproduces `compute` from the topology alone; over-threshold cone identical regardless of layout). `[Coverage: UNIT_TEST]` |
| Elaboration, ladder, paint and workspace-restore perf budgets; 100K in-app trace with no jank; CXP entitlement smoke | **Manual** — wall-clock budgets are recorded, not asserted; the in-app 100K trace is a manual confirmation. `[Coverage: MANUAL]` |

---

## 10. About Box (shared `crux_about_dialog` surface)

### What it does

The About box is the cross-suite [`CruxAboutDialog`](../crux-shared/packages/crux_about_dialog) surface, adopted by NetCrux in place of the old Material `showAboutDialog` stub. NetCrux supplies its branding, build metadata, edition label, localized chrome strings, an app icon, and the action buttons; the shared widget renders the header (icon, title, tagline, chips), the Version / Platform sections, the action-button row, and the Ferrite Engineering branding banner. It presents as a modal dialog on desktop and a pushed full-screen route on mobile.

Tier and beta-period chips are driven by `crux_license` providers **inside** the shared widget (`licenseTierProvider`, `betaPeriodProvider`), so the EDU badge and the "Public Beta" chip stay consistent without per-app wiring. The dialog is **not** feature-gated — it is available to every tier; only the chips change.

NetCrux ships **no attribution sections** (unlike WaveCrux, it uses no third-party engine such as wellen) and exactly **two** action buttons: **Visit Website** and **Copy Version Info**.

### Setup

- Any NetCrux build (no design needs to be open).
- For the EDU-badge check, run a build whose `licenseTierProvider` resolves to `LicenseTier.edu` (or override it).

### Steps and expected behavior

1. Open the About box: **Help → About NetCrux**, or the command palette → "About NetCrux", or the `openAbout` action. Expected: the dialog (desktop) / route (mobile) opens.
2. **Header.** The schematic app icon (`Icons.account_tree_outlined`, primary-tinted, ~72 dp) renders above the title **"About NetCrux"** and the tagline **"Modern netlist and schematic viewer for hardware engineers"**.
3. **Version section.** Shows Version, Build, and Commit rows from `aboutBuildInfoProvider` (version/build from `package_info_plus`; commit is `dev` until CI injects a SHA).
4. **Platform section.** Shows OS, Architecture, Flutter, and Dart rows. OS resolves to the host (`macOS …` / `Linux …` / `Windows …`); the others are best-effort (`unknown`) until CI injects them, except Dart which reads `Platform.version`.
5. **Branding banner.** The bottom banner shows the square Ferrite Engineering logo, the company tagline ("Ferrite Engineering"), and "© 2025 Ferrite Engineering".
6. **Public Beta chip.** While `kBetaPeriod` is `true` (the `betaPeriodProvider` default), a red "Public Beta" chip appears in the header. With a build where `betaPeriodProvider` resolves to `false`, the chip is absent.
7. **Edition chip / EDU badge.** Open-core build: no edition chip ("Pro" / "Enterprise" absent). EDU build: the `EditionBadge` ("EDU") renders in the header.
8. **Visit Website.** Tapping **Visit Website** opens `https://ferriteengineering.com` in the system browser.
9. **Copy Version Info.** Tapping **Copy Version Info** copies the structured paragraph (`NetCrux <version> (build <n>)`, optional `Edition:` line, `Git SHA:`, `OS:`, `Architecture:`, `Flutter:`, `Dart:`) to the clipboard and shows a "Version info copied" snackbar. The button is disabled only while build info is still loading / failed.
10. **Locale sweep.** Re-open in en / zh_CN / ja / ko — all chrome strings localize, no RenderFlex overflow.

### Tier-gate scenarios

The About box is **not** tier-gated; it opens for every tier. Only the header chips differ:

- **`kBetaPeriod = true` (beta, current default).** "Public Beta" chip shown for every tier. Open-core: no edition chip. EDU: "EDU" badge. Pro/Enterprise: the corresponding edition chip.
- **`kBetaPeriod = false` (post-beta).** No "Public Beta" chip. Edition chip / EDU badge behavior is unchanged (driven by `licenseTierProvider`, independent of the beta flag).

### Edge cases

- **Build info fails to resolve.** The Version/Platform section hides (the shared widget's `error` branch) and **Copy Version Info** stays disabled — no crash, the rest of the dialog renders.
- **Missing branding asset.** The banner logo falls back to an empty box (the shared banner's `errorBuilder`); text still renders.
- **Mobile route form.** On a phone/tablet the dialog is a full-screen route with an app-bar back button rather than a modal.

### Automation Assessment

| Capability | Assessment |
|------------|------------|
| Dialog opens; shows title / version / SHA / company from stubbed providers | **Strong** — `test/features/about/netcrux_about_dialog_test.dart` content group. `[Coverage: WIDGET]` |
| Locale sweep en/zh_CN/ja/ko renders without exception | **Strong** — same test, locale-sweep group. `[Coverage: WIDGET]` |
| Edition chip hidden for open-core; EDU badge for `LicenseTier.edu` | **Strong** — same test, edition-chip group. `[Coverage: WIDGET]` |
| "Public Beta" chip toggles with `betaPeriodProvider` | **Strong** — same test, beta-indicator group (override true/false). `[Coverage: WIDGET]` |
| Both action buttons present; Copy Version Info enabled once build info loads | **Strong** — same test, action-button group. `[Coverage: WIDGET]` |
| Visit Website launches the system browser; clipboard receives the structured paragraph | **Manual** — needs a real `url_launcher` / clipboard host. `[Coverage: MANUAL]` |
| Shared-widget rendering (banner, scroll body, chips) | **Inherited** — covered by the `crux_about_dialog` package suite. `[Coverage: PACKAGE]` |

---

## 11. Beta Release Infrastructure

Three features land together because they share one loop: the update check observes the authoritative server time, the persisted watermark hardens the beta-expiry clock, and the issue reporter is how a user tells us the whole thing misbehaved. All three are Open Core, available to every tier, and carry **no tier badge and no feature gate** — a user who cannot report a bug is a user whose bug never gets fixed, and a user stuck on a stale build is a user filing bugs we already fixed.

Implementation note for the verifier: the moving parts live in the cross-suite packages `crux_updates`, `crux_issue_reporter` and `crux_license` (under `crux-shared/packages/`). NetCrux supplies the configuration, the ARB-backed string adapters, the persisted settings, and the privacy-scrubbed session snapshot. When something reads "the package does X", the behaviour is covered by that package's own suite; the checks below cover NetCrux's binding of it.

### 11.1 Update mechanism — launch / periodic / manual checks and the update banner

#### What it does

NetCrux fetches a small public JSON manifest from `https://updates.netcrux.app/manifest.json` and compares its `latest.version` against the running build. When something newer exists, a dismissible strip appears above the workspace: *"NetCrux 1.2.0 is available."* with **View Changes** (opens the release's changelog URL) and **Update Now** (opens `https://netcrux.app/download`). There is no in-place download or relaunch — "Update Now" is a deep link.

Three things trigger a check: app launch, a 24-hour periodic timer, and app resume. All three are **gated** on Settings → General → "Automatically check for updates" (default on). The **manual** check — Help menu, command palette, or the About box's **Check for Updates** button — ignores that setting and always runs.

The request is one `GET` for a public JSON file with a single `User-Agent` of the form `NetCrux/1.2.0 (macOS 15.0)`. No design, netlist, file or identity data is transmitted, ever.

#### Setup

- Any desktop NetCrux build. No design needs to be open.
- To exercise the "update available" path without a real release, stand up a local manifest and point the build at it, or override `updateStatusProvider` in a debug build. The manifest shape is documented in `crux-shared/packages/crux_updates/README.md` → "Manifest format".
- To exercise the failure path, disconnect the network (or block `updates.netcrux.app` in `/etc/hosts`).

#### Steps and expected behavior

1. **Launch with auto-check on (the default).** Expected: no visible change when the build is current. Nothing flashes, no spinner, no toast — a check that finds nothing must be silent.
2. **Launch against a manifest advertising a newer version.** Expected: the banner appears above the workspace content, below the window chrome, reading `NetCrux <version> is available.` The workspace is fully usable behind it.
3. **View Changes.** Expected: the system browser opens the manifest's `changelog_url`. When the manifest carries no `changelog_url`, the **View Changes** button is absent entirely (not disabled).
4. **Update Now.** Expected: the system browser opens `https://netcrux.app/download`.
5. **Dismiss.** Expected: the strip disappears and stays gone for the rest of the session. Re-launching (still on the same offered version) brings it back; a *newer* version offered later also brings it back.
6. **Mandatory update.** With a manifest carrying `"mandatory": true` (or a running build below `min_supported_version`), expected: the banner renders with **no close button at all**. There is no way to hide it short of updating.
7. **Manual check, up to date.** Help → Check for Updates (or the command palette, or the About box button). Expected: a transient *"Checking for updates…"* snackbar, replaced on completion by *"You're on the latest version (1.2.3)."*
8. **Manual check, update available.** Expected: the in-flight snackbar is replaced by nothing — the banner is what reports it.
9. **Manual check, offline.** Expected: *"Couldn't check for updates."* The app is otherwise unaffected; no dialog, no retry loop, no error in any feature flow.
10. **Auto-check off.** Settings → General → toggle "Automatically check for updates" off. Quit and relaunch against a manifest advertising a newer version. Expected: **no banner**. Then run Help → Check for Updates. Expected: the banner appears — a manual check always runs.
11. **Settings persistence.** Toggle off, quit, relaunch, open Settings → General. Expected: the toggle is still off.
12. **Web viewer.** Open the read-only web viewer against a manifest advertising a newer version. Expected: **no banner ever** — a web app self-updates on reload. The check itself still runs (it is what supplies the `server_time` watermark; see §11.3).

#### Diagnostics-assisted verification

The banner is driven entirely by `updateStatusProvider`'s four-state value. A build stuck showing (or not showing) the banner is either a wrong `UpdateStatus` or a stale dismissal — check which by running a manual check and watching which snackbar appears: a *"Couldn't check for updates"* toast with no banner means the fetch failed; no toast and no banner means the check reported "current".

#### Edge cases / break-it tests

- **Malformed manifest.** Serve `{` or `{"latest":{}}`. Expected: the check resolves as a failure (typed, non-fatal) — no crash, no banner, no exception dialog. `UpdateManifest.tryParse` fails soft by contract.
- **Manifest with an unparseable `version`.** Expected: same as malformed — treated as no update.
- **Type-mismatched optional field** (e.g. `"mandatory": "yes"`). Expected: the field is dropped, the rest of the manifest is honoured.
- **Check racing startup.** Launch and immediately open the About box. Expected: no comparison against an unknown version — until build info resolves the no-op service is in place, so the worst case is "reports current".
- **Container teardown mid-fetch.** Close the last tab / quit while a check is in flight. Expected: no post-dispose provider exception in the console.

#### Tier-gate scenarios

The update mechanism is **not tier-gated in either phase**. It is release infrastructure, not a feature.

- **`kBetaPeriod = true` (beta, current default).** Available at every tier including Open Core. No `PRO`/`ENT` badge on the Help-menu item or the command-palette row — `NetcruxAction.checkForUpdates` declares `LicenseTier.openCore`, so no badge is rendered and no `" (PRO)"` suffix is appended to the native menu-bar label.
- **`kBetaPeriod = false` (post-beta).** Identical. Verify explicitly that Check for Updates does **not** raise `NetcruxUpgradeDialog` at any tier, and that the command-palette row still carries no badge.

#### Automation Assessment

| Capability | Assessment |
|------------|------------|
| Config values: product name, manifest URI, download page, no store URIs, `checkOnMobile` false | **Strong** — `test/features/update/netcrux_update_overrides_test.dart`. `[Coverage: UNIT]` |
| Every desktop platform (and web) resolves "Update Now" to the download page | **Strong** — same file. `[Coverage: UNIT]` |
| Root overrides bind config / build info / auto-check setting / URL launcher | **Strong** — same file. `[Coverage: UNIT]` |
| State machine: launch check runs, reports available / current | **Strong** — `test/features/update/update_status_state_machine_test.dart`. `[Coverage: UNIT]` |
| Auto-check off suppresses launch **and** every scheduled path | **Strong** — same file. `[Coverage: UNIT]` |
| Manual `checkNow` runs regardless of the setting | **Strong** — same file. `[Coverage: UNIT]` |
| Periodic timer keeps checking | **Strong** — same file (short `checkInterval`). `[Coverage: UNIT]` |
| A failed check resolves to a typed error, never a throw | **Strong** — same file. `[Coverage: UNIT]` |
| Banner: hidden when current / errored, shown when available | **Strong** — `test/features/update/widgets/update_banner_mount_test.dart`. `[Coverage: WIDGET]` |
| Banner: **mandatory update has no dismiss affordance** | **Strong** — same file. `[Coverage: WIDGET]` |
| Banner: dismissal hides the strip for the session | **Strong** — same file. `[Coverage: WIDGET]` |
| Banner: Update Now / View Changes open the right URLs; View Changes absent without a changelog | **Strong** — same file. `[Coverage: WIDGET]` |
| Banner: never renders on the web build | **Strong** — same file (`isWeb` seam). `[Coverage: WIDGET]` |
| Banner: four-locale sweep, 44 dp touch targets | **Strong** — same file. `[Coverage: WIDGET]` |
| Settings toggle: default on, reflects persisted off, writes through, 44 dp, four-locale | **Strong** — `test/features/settings/screens/settings_auto_update_tile_test.dart`. `[Coverage: WIDGET]` |
| Settings codec round-trip + missing-key-loads-as-enabled | **Strong** — `test/services/settings/netcrux_settings_codec_test.dart`. `[Coverage: UNIT]` |
| ARB adapter: five-locale parity, version interpolation, product name in the banner copy | **Strong** — `test/core/updates/netcrux_update_strings_test.dart`. `[Coverage: WIDGET]` |
| About-box **Check for Updates** button runs a manual check | **Strong** — `test/features/about/netcrux_about_dialog_beta_actions_test.dart`. `[Coverage: WIDGET]` |
| Action reaches menu bar + command palette from the descriptor table | **Strong** — `test/core/shortcuts/action_surface_conformance_test.dart` + `workspace_action_dispatch_table_test.dart`. `[Coverage: UNIT]` |
| Live fetch against the real manifest endpoint; real browser launch | **Manual** — needs the network and a host browser. `[Coverage: MANUAL]` |
| On-resume re-check | **Manual** — needs a real app-lifecycle suspend/resume. `[Coverage: MANUAL]` |
| Web build never shows the banner, in a real browser | **Manual** — `[Coverage: MANUAL]` |

---

### 11.2 Beta issue reporter — in-app GitHub bug reports

#### What it does

**Help → Submit Issue** (also in the command palette and the About box) opens a dialog that collects diagnostic context, lets the user review and switch off any part of it, previews the exact markdown that will be filed, and then opens a pre-filled GitHub new-issue page at `Ferrite-Engineering/netcrux` with the report on the clipboard.

Four categories, each a toggle:

| Category | Default | Content |
|---|---|---|
| **App & Environment** | always on, locked | Product, app version, build SHA, platform, OS, architecture, screen DPI, locale, Flutter/Dart SDK versions |
| **Session State** | on | NetCrux's own snapshot — tab and pane counts, source-file count, source *languages*, elaboration state, module / cell / net counts, whether a schematic is laid out, whether there is a selection or trace overlay, which analysis panes hold a result |
| **Diagnostics** | on | The last 100 WARNING+ ring-buffer entries plus the last 20 at any level |
| **Screenshot** | on, desktop only | A Flutter-layer capture of the app window, written to the OS temp directory and revealed in the file manager on submit |

**The privacy contract is the point.** The report carries **no file contents, no file paths, and no identifiers taken from the user's RTL** — only counts, format/language names and environment metadata. That is why the Session State section reports "3 source files, languages verilog + systemVerilog + vhdl, 2 modules, 4 cells" rather than naming anything. Two deliberate consequences worth knowing as a verifier:

- The Yosys **executable path** is never reported — only `available` / `unavailable` / `not probed`.
- Yosys **stderr** is deliberately *not* folded into the Diagnostics category, even though NetCrux has it and the tab diagnostics drawer shows it: Yosys quotes source-file paths verbatim in its errors.

#### Setup

- A desktop NetCrux build (the Screenshot category is desktop-only).
- Ideally a loaded design so the Session State section has something to report.
- A GitHub account, or at least a browser, to confirm the new-issue page opens pre-filled.

#### Steps and expected behavior

1. **Open.** Help → Submit Issue, or the command palette, or the About box's **Submit Issue** button. Expected: a modal dialog on desktop, titled "Submit Issue".
2. **Summary field.** Type a one-line description. Expected: it becomes the GitHub issue title. Leaving it blank falls back to the dialog title.
3. **Privacy callout.** Expected: the notice above the tiles states that file contents and file paths are never included.
4. **Category tiles.** Expected: four tiles. **App & Environment** carries a lock glyph and cannot be switched off (screen-reader label: "Always included"). The other three toggle.
5. **Preview.** Expand "Preview issue body". Expected: the exact markdown, updating live as tiles are toggled. Switch off Session State — the `## Session State` heading disappears from the preview.
6. **Read the Session State section carefully.** Expected: counts, `available`/`unavailable`, language names, `yes`/`no`. **Expected absent:** any `/` or `\`, any source filename, any module / instance / net name from your design, the Yosys binary path.
7. **Submit.** Expected: the body lands on the clipboard, the GitHub new-issue page opens in the browser pre-filled (title, labels `bug` + `user-report`, and the `bug_report.yml` issue form), and — when the Screenshot tile is on — a toast naming where the PNG was written, with the file revealed in Finder / Explorer / the file manager.
8. **Over-long report.** With a long session log, submit again. Expected: the URL no longer carries the body (it would exceed the ~6000-character cap GitHub tolerates), the toast changes to the "paste from your clipboard" wording, and pasting reproduces the full report.
9. **Cancel.** Expected: nothing is copied, nothing opens.
10. **Locale sweep.** Re-open in zh_CN / ja / ko. Expected: the dialog chrome, tile titles, descriptions, buttons and toasts are all localized. The **issue body itself stays English** — it is authored for the maintainers reading it in the repository, and a mixed-language body makes triage harder.

#### Diagnostics-assisted verification

The Diagnostics category is fed by a 500-entry ring buffer attached to `package:logging` in `bootstrap()` *before the first provider is constructed*, plus `FlutterError` / `PlatformDispatcher` error capture. To confirm the ring is live: trigger a recoverable failure (open a design with Yosys unavailable, or corrupt `workspace.json` and relaunch — see §9.4), then open the reporter. Expected: the failure appears in the Diagnostics preview.

Note for this release: NetCrux's own `lib/` does not yet emit through `package:logging`, so the ring's content in a healthy session comes from captured Flutter errors rather than from app logging. An empty ring renders the `(no log entries captured)` placeholder rather than an empty section.

#### Edge cases / break-it tests

- **No design open, no tabs.** Expected: the reporter still opens; Session State reports `Open tabs: 0`, `Elaboration: no design`, zero counts. It is never omitted or empty.
- **Elaboration in flight.** Open a design and open the reporter immediately. Expected: `Elaboration: in progress` rather than a stale "succeeded".
- **Elaboration failed.** Point at a broken source. Expected: `Elaboration: failed` — and still no path in the body.
- **Split panes / two tabs.** Expected: `Panes: 2`, `Open tabs: 2`, and the design counts describe the **active** tab, not the first one. Switch tabs, re-open the reporter, confirm the counts follow.
- **Every optional tile off.** Expected: the report still contains the App & Environment section and submits successfully.
- **Screenshot tile on mobile/web.** Expected: the tile is not rendered at all.

#### Tier-gate scenarios

The reporter is **open to every tier in both phases** — no badge, no `FeatureGate`, no upgrade dialog. This is deliberate: gating the bug-report path would silence exactly the users most likely to hit a bug.

- **Target repository.** Reports are filed against **`Ferrite-Engineering/netcrux`**, the open-core source repo. Confirm the opened URL's path begins `/Ferrite-Engineering/netcrux/issues/new`. `NetcruxAction.submitIssue` declares `LicenseTier.openCore`, so the Help-menu item carries no `" (PRO)"` suffix and the command-palette row carries no badge.
- **Independent of `kBetaPeriod`.** The slug is a fixed constant — the tracker moved to the open-core repo at the 1.0 launch, while the gating flag flips on its own schedule. Build with `--dart-define=BETA_PERIOD=false` and verify the target is unchanged and the action still activates at Open Core tier without raising `NetcruxUpgradeDialog`.

#### Automation Assessment

| Capability | Assessment |
|------------|------------|
| **PRIVACY: a Session State body from the real contributor carries no file paths** | **Strong** — `test/features/issue_reporter/providers/netcrux_issue_session_context_test.dart`, driven from a populated session (three real-looking source paths, a Yosys path, a design with named modules/cells/nets, a selection). Asserts no `/`, no `\`, and each specific string explicitly. `[Coverage: UNIT]` |
| PRIVACY: the structured attribute map carries no paths either | **Strong** — same file. `[Coverage: UNIT]` |
| Session State reports **non-zero** counts from a populated session | **Strong** — same file. This is the companion to the privacy assertion: an all-zero body would satisfy "no paths" just as happily, so the counts are pinned separately. `[Coverage: UNIT]` |
| The contributor resolves with real counts through the chrome `ProviderScope` the dialog uses | **Strong** — same file. Guards the failure mode where the contributor materializes in a scope that cannot reach the tab manager and silently reports zeros. `[Coverage: UNIT]` |
| Counts follow the **active tab** (per-tab container, not the root scope) | **Strong** — same file (the harness drives a real `TabContainerManager`). `[Coverage: UNIT]` |
| Empty workspace / in-flight elaboration produce a usable snapshot | **Strong** — same file. `[Coverage: UNIT]` |
| Degrades without a tab manager (bare container) instead of throwing | **Strong** — same file. `[Coverage: UNIT]` |
| Config: product name, beta repository slug, `bug_report.yml` template, labels, new-issue URL, screenshot prefix | **Strong** — `test/features/issue_reporter/netcrux_issue_reporter_overrides_test.dart`. `[Coverage: UNIT]` |
| Unwired config throws (the package's loud default) and NetCrux's override replaces it | **Strong** — same file. `[Coverage: UNIT]` |
| Overlay category seam stays no-op on an Open Core build | **Strong** — same file. `[Coverage: UNIT]` |
| Yosys stderr is **not** wired into the diagnostics category | **Strong** — same file. `[Coverage: UNIT]` |
| ARB adapter: five-locale parity across all 21 strings, path interpolation | **Strong** — `test/core/issue_reporter/netcrux_issue_reporter_strings_test.dart`. `[Coverage: WIDGET]` |
| About-box **Submit Issue** button opens the reporter | **Strong** — `test/features/about/netcrux_about_dialog_beta_actions_test.dart`. `[Coverage: WIDGET]` |
| Action reaches menu bar + command palette from the descriptor table | **Strong** — `action_surface_conformance_test.dart` + `workspace_action_dispatch_table_test.dart`. `[Coverage: UNIT]` |
| Dialog layout, tile toggling, preview, 48 dp touch targets, string-length sweep | **Inherited** — covered by the `crux_issue_reporter` package suite. `[Coverage: PACKAGE]` |
| Clipboard write, browser launch, screenshot capture + temp-dir reveal | **Manual** — needs real platform channels and a host browser/file manager. `[Coverage: MANUAL]` |
| The GitHub form actually opens pre-filled at the right repository | **Manual** — `[Coverage: MANUAL]` |
| Over-long-body fallback in a real browser | **Manual** — `[Coverage: MANUAL]` |

---

### 11.3 Beta expiry — per-release build shelf life

#### What it does

Each public-beta drop carries its own hard expiry date, injected at build time with `--dart-define=BETA_EXPIRY=<yyyymmdd>` (e.g. `BETA_EXPIRY=20260901`). Inside a warning window (7 days by default, overridable with `--dart-define=BETA_EXPIRY_WARNING_DAYS=<n>`) the app shows a **dismissible** strip: *"NetCrux Beta expires in 3 days. Download the latest build."* On and after the expiry date it shows a **blocking, non-dismissable** modal with two ways out: **Download latest build** and **Quit NetCrux**.

Two properties are load-bearing:

- **Absent or `0` means the build never expires.** Every developer build and every post-beta production build is unaffected — expiry only applies while `kBetaPeriod` is `true`.
- **The device clock alone is not trusted.** Expiry is reckoned against the *later* of the device clock and the most recent authoritative `server_time` the update check has observed and persisted. Winding the clock back cannot defer expiry below that watermark. A user who has never been online, or who moves the clock *forward*, is reckoned by the device clock — accepted, because the mechanism retires stale builds rather than resisting a determined attacker.

The status is evaluated at startup and on app resume, never mid-session, so an in-progress elaboration or layout is never interrupted.

#### Setup

Build with an injected expiry:

```bash
# Inside the warning window (pick a date 3 days out).
flutter run -d macos --dart-define=BETA_EXPIRY=<yyyymmdd>
# Already expired.
flutter run -d macos --dart-define=BETA_EXPIRY=20200101
# Never expires (the default developer build).
flutter run -d macos
```

To exercise the clock-tampering path you also need a build that has completed at least one successful update check (which persists the watermark under the `netcrux.update.observedServerTime` preference key).

#### Steps and expected behavior

1. **No `BETA_EXPIRY`.** Expected: nothing. No banner, no modal, at any date.
2. **Expiry more than the warning window away.** Expected: nothing.
3. **Inside the warning window.** Expected: a tertiary-toned strip above the workspace reading *"NetCrux Beta expires in N days. Download the latest build."* with an inline **Download** action and a close button. N matches the whole calendar days remaining.
4. **Download from the banner.** Expected: the system browser opens `https://netcrux.app/download` — the same target the update banner uses.
5. **Dismiss the banner.** Expected: it disappears. It stays gone for the session, and **returns on the next app resume** — a returning user is reminded again.
6. **Expired.** Expected: a dimmed, input-blocked workspace behind a centered card: *"Beta build expired"*, the explanatory body, **Download latest build**, and **Quit NetCrux**. There is no close affordance and the system back gesture does not dismiss it.
7. **Quit from the modal.** Expected: the app terminates. This action is load-bearing on Windows and Linux, where the in-app close caption button sits *behind* the modal barrier (macOS's native traffic lights are unaffected).
8. **Layering against the update banner.** With both an available update and an expired build, expected: the blocking modal covers the update banner. An expired build must not present a second, competing call to action.
9. **Clock rollback.** On a build that has observed a server time past the expiry, set the system clock back a year and relaunch. Expected: still expired. Repeat with the clock set back on a build inside the warning window whose watermark is inside the window — expected: still warning.
10. **Fresh offline install.** No update check has ever succeeded, so no watermark exists. Expected: expiry is reckoned by the device clock, exactly as before the hardening — not "fail closed".

#### Diagnostics-assisted verification

The status is a pure function of three inputs: the injected date, the warning window, and the trusted "now". If the observed behaviour disagrees with the calendar, check the persisted watermark (`netcrux.update.observedServerTime` in `SharedPreferences`) — it is monotonic and may be *ahead* of the device clock by design.

#### Edge cases / break-it tests

- **Invalid `BETA_EXPIRY`.** `20261301` (month 13), `20260230` (Feb 30), a negative number. Expected: treated as "never expires" — a malformed build-time constant must not brick the app.
- **Expiry date exactly today.** Expected: **expired** at the start of that calendar day, not at the end of it.
- **One day remaining.** Expected: the singular form of the banner message (`=1` ICU plural case), in every locale.
- **Crossing the boundary while suspended.** Suspend inside the warning window, change the system date past expiry, resume. Expected: the blocking modal appears on resume, without a relaunch.
- **A dismissed banner and a resume.** Dismiss, suspend, resume. Expected: the banner is back.

#### Tier-gate scenarios

Beta expiry is **not tier-gated** — it is a property of the *build*, not of the licence.

- **`kBetaPeriod = true` (beta, current default).** The mechanism is armed. A build with an injected `BETA_EXPIRY` warns and then blocks, identically at Open Core, EDU, Pro and Enterprise tiers. A Pro licence does not extend a beta build's shelf life.
- **`kBetaPeriod = false` (post-beta).** `kBetaExpiry` resolves to `null` regardless of what `--dart-define=BETA_EXPIRY` was set to, so a production build **never expires**. Verify by building with `BETA_EXPIRY` set to a past date and `kBetaPeriod` flipped: expected no banner and no modal.

#### Automation Assessment

| Capability | Assessment |
|------------|------------|
| Status → UI mapping (notApplicable / active pass through; expiringSoon banner; expired modal) | **Strong** — `test/features/beta_expiry/widgets/beta_expiry_gate_test.dart`. `[Coverage: WIDGET]` |
| Banner dismissal hides the strip for the session | **Strong** — same file. `[Coverage: WIDGET]` |
| Banner Download opens the NetCrux download page | **Strong** — same file (launcher seam). `[Coverage: WIDGET]` |
| Expired modal offers **no** dismiss affordance and blocks the back gesture | **Strong** — same file (`PopScope.canPop == false`). `[Coverage: WIDGET]` |
| Expired modal Download + Quit are both wired | **Strong** — same file (exit seam). `[Coverage: WIDGET]` |
| 44 dp touch targets on every banner and modal control | **Strong** — same file. `[Coverage: WIDGET]` |
| Four-locale sweep of the banner (incl. the `=1` plural) and the modal | **Strong** — same file. `[Coverage: WIDGET]` |
| **Clock rollback cannot revive an expired build** | **Strong** — same file, clock-tampering group: device clock alone says "active", the trusted clock says "expired". `[Coverage: UNIT]` |
| Clock rollback cannot escape the warning window | **Strong** — same file. `[Coverage: UNIT]` |
| A device clock *ahead* of the watermark still wins | **Strong** — same file. `[Coverage: UNIT]` |
| No observed server time falls back to the device clock (offline install) | **Strong** — same file. `[Coverage: UNIT]` |
| A build with no injected expiry never expires | **Strong** — same file. `[Coverage: UNIT]` |
| Server-time watermark: monotonic, persisted, reloaded on launch, corrupt value ignored | **Strong** — `test/features/update/providers/observed_server_time_provider_test.dart`. `[Coverage: UNIT]` |
| The loop: manifest `server_time` → persisted store → `crux_license`'s `observedServerTimeProvider` | **Strong** — `test/features/update/netcrux_update_overrides_test.dart`. `[Coverage: UNIT]` |
| Date parsing / status boundaries / warning-window arithmetic | **Inherited** — covered by the `crux_license` package suite (`beta_expiry_test.dart`). `[Coverage: PACKAGE]` |
| Real `--dart-define=BETA_EXPIRY` build actually warns / blocks | **Manual** — needs a real build per date. `[Coverage: MANUAL]` |
| On-resume re-evaluation across a real suspend | **Manual** — `[Coverage: MANUAL]` |
| Quit from the modal on Windows / Linux custom chrome | **Manual** — the failure mode is platform-specific. `[Coverage: MANUAL]` |
| Real system-clock rollback end-to-end | **Manual** — `[Coverage: MANUAL]` |

---

### 11.4 Tier badging during the beta

#### What it does

The suite-wide beta policy is **badge but do not block**: every Pro/Enterprise action stays visible and activatable during the beta, while carrying a chip that communicates the tier it will require afterwards. NetCrux declares the tier once, on `NetcruxActionRequiredTier.requiredTier`, and each discovery surface renders it from there — a `NetCruxFeatureTierBadge` in the command palette, and a localized `" (PRO)"` / `" (ENT)"` suffix on the native menu bar (which can only render a `String`, never a widget).

#### Setup

Any NetCrux build. To exercise the post-beta path, override `betaPeriodProvider` to `false` (or flip `kBetaPeriod`) and set `licenseTierProvider` to `LicenseTier.openCore`.

#### Steps and expected behavior

1. **Command palette.** Open it and scroll to a Pro action (e.g. "Show CDC Analysis Pane", "Show FSM Bubble Diagram", "Load Comparison Netlist"). Expected: a `PRO` chip to the right of the label.
2. **Native menu bar.** Open the same action's menu. Expected: the label ends in `" (PRO)"`.
3. **Open Core actions carry nothing.** Check "Check for Updates", "Submit Issue", "About NetCrux", and every clear/dismiss action. Expected: no chip, no suffix.
4. **Activation during beta.** With `kBetaPeriod = true` and an Open Core tier, activate a badged Pro action. Expected: it **runs** — the badge is communication, not enforcement. On an Open Core build the Pro seam resolves to its no-op, so the pane opens showing its empty-state explainer.
5. **Activation post-beta at an insufficient tier.** With `kBetaPeriod = false` and Open Core tier, activate the same action. Expected: `NetcruxUpgradeDialog`, naming the feature and the tier that unlocks it. Nothing is silently no-oped.
6. **Beta indicator chip.** Open the About box. Expected: a red **Public Beta** chip in the header while `kBetaPeriod` is `true`, absent when it is `false`.
7. **Locale sweep.** Repeat 1–2 and 6 in zh_CN / ja / ko. Expected: the chips and the menu suffix are localized; no overflow.

#### Edge cases / break-it tests

- **A new Pro action that forgets its tier.** Add one and leave `requiredTier` at `openCore`. Expected: it ships without a badge — this is the defect the convention exists to prevent, and it is why tier is declared once on the descriptor rather than per surface.
- **Toolbar.** Toolbar placement is opt-in and no Pro action is on the toolbar today; if one is added, the conformance test cross-checks the descriptor against the keyed button.

#### Tier-gate scenarios

This section *is* the tier-gate scenario. Both phases are covered by steps 4 and 5 above.

#### Automation Assessment

| Capability | Assessment |
|------------|------------|
| Every Pro/Enterprise action declares a non-`openCore` `requiredTier`; everything else stays Open Core | **Strong** — `test/core/shortcuts/netcrux_action_test.dart` (`NetcruxActionRequiredTier` group, exhaustive). `[Coverage: UNIT]` |
| Command palette renders `NetCruxFeatureTierBadge` from `requiredTier` | **Strong** — `test/features/command_palette/widgets/command_palette_dialog_test.dart`. `[Coverage: WIDGET]` |
| Native menu bar appends the localized tier suffix | **Strong** — `test/core/shortcuts/action_tier_label_test.dart` + `test/features/menu_bar/widgets/desktop_menu_bar_test.dart`. `[Coverage: UNIT/WIDGET]` |
| Every surface agrees with the descriptor table (no per-surface drift) | **Strong** — `test/core/shortcuts/action_surface_conformance_test.dart`. `[Coverage: UNIT]` |
| **Beta short-circuit admits every Pro action at Open Core tier** | **Strong** — `test/features/workspace/screens/workspace_screen_gating_test.dart`. `[Coverage: WIDGET]` |
| **Post-beta, no Pro action reaches its opener at an insufficient tier** | **Strong** — same file. `[Coverage: WIDGET]` |
| Post-beta at a satisfied tier, every Pro action reaches its opener | **Strong** — same file. `[Coverage: WIDGET]` |
| About-box **Public Beta** chip toggles with `betaPeriodProvider` | **Strong** — `test/features/about/netcrux_about_dialog_test.dart` beta-indicator group + `netcrux_about_dialog_beta_actions_test.dart`. `[Coverage: WIDGET]` |
| Visual polish of the chip / suffix at each locale | **Manual** — `[Coverage: MANUAL]` |
---

## 18. macOS release-build file access (sandbox entitlement)

- **What it does.** NetCrux's macOS **release** build must be able to present
  `NSOpenPanel`. The `file_selector` plugin refuses to open the panel unless the
  app declares `com.apple.security.files.user-selected.read-write`, even when
  `com.apple.security.app-sandbox` is `false`. Debug builds mask the problem,
  because `DebugProfile.entitlements` carries broader permissions.
- **Why this section exists.** The 2026-07-16 marketing-screenshot session found
  the release build dead on this path: every picker invocation surfaced
  `PlatformException(ENTITLEMENT_NOT_FOUND, ...)`. Opening a file by CLI argument
  still worked, which is exactly why it survived earlier testing — **the failure
  is invisible to anyone who launches with a path.** Fixed 2026-07-21 by
  mirroring WaveCrux's `Release.entitlements` in both this repo and the Pro
  overlay.
- **Setup.** `flutter build macos --release`, then launch the produced `.app`
  from Finder (not `flutter run`, and not with a positional path argument).
- **Steps and expected behavior.**
  1. With no file loaded, invoke **Cmd+Shift+O (Open Source Files)**. Expected: the macOS open panel
     appears. Failure mode to watch for: a snackbar reading
     `ENTITLEMENT_NOT_FOUND`.
  2. Choose a file. Expected: it loads normally.
  3. Confirm the key is present in the shipped binary:
     `codesign -d --entitlements - <path>.app` must list
     `com.apple.security.files.user-selected.read-write`.
- **Edge cases.** Drag-and-drop and CLI-argument opening bypass the panel
  entirely and will keep working even when the entitlement is missing — so
  neither is a substitute for step 1.
- **Tier-gate scenarios.** None. File opening is open-core and ungated; the
  behavior is identical under `kBetaPeriod = true` and `false`.

### Automation Assessment

| Check | Automatable? | How |
|---|---|---|
| Entitlement key present in both repos' `Release.entitlements` | **Yes** | Static test parsing the plist; guards against a Flutter-tooling regeneration silently dropping it |
| Release `.app` ships the entitlement | Partly | `codesign -d --entitlements -` in release CI, post-build |
| Open panel actually appears | **No** | Requires a signed release build and a real window server — manual, per release |

## Adding a section

Add a new top-level section the same day the corresponding feature ships. Do not pre-write speculative content — the section is created when an item is ready to be verified.

---

## 99. Sign-off

- [ ] All shipped-feature sections above signed off
- [ ] Open Core SHA: ____________________
- [ ] Verifier: ____________________
- [ ] Date: ____________________
- [ ] Platforms: ____________________
