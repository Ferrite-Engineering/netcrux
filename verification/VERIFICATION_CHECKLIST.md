# NetCrux (Open Core) — Verification Checklist

> **Purpose.** Quick pre-release sign-off list. For step-by-step instructions, fixture inventory, and rationale, see `VERIFICATION_GUIDE.md` (sibling, this folder).
>
> **Pro overlay.** If you are signing off a Pro build, run this checklist first, then run the Pro overlay's own checklist for the Pro/Enterprise delta.

> **Coverage markers.** Every bullet carries a `[Coverage: …]` tag. Bullets tagged `WIDGET` or `INTEGRATION_TEST` (without `pending`) are protected by CI and may be skipped unless the relevant test files changed. Everything else must be exercised by hand. Full taxonomy in `VERIFICATION_GUIDE.md` §1.3.

---

## Release metadata

- NetCrux version: ____________________
- Open Core SHA: ____________________
- Verifier: ____________________
- Date: ____________________
- Platform(s) tested: ____________________

---

## Pre-flight

- [ ] All fixtures present under `verification/fixtures/` — `[Coverage: MANUAL]`
- [ ] Open Core baseline diagnostics report captured (once a diagnostics panel exists): `oc_baseline_report_<release>.txt` — `[Coverage: MANUAL]`

---

## Foundation

- [ ] NetlistModel domain types (§3.1) — `fromJson`/`toJson` round-trip; both top-attr encodings (`'1'` / `'00000001'`) detected as top; `modules`-missing → `FormatException` — `[Coverage: UNIT]` (`test/domain/models/netlist/netlist_model_test.dart` + per-type tests)
- [ ] Yosys elaboration pipeline (§3.2) — availability probe reason codes; runner temp-file JSON + empty-JSON-as-failure; parser → `NetlistModel` / `YosysJsonParseException`; stderr → structured diagnostics — `[Coverage: UNIT]` (`yosys_availability_provider_test.dart`, `yosys_runner_provider_test.dart`, `yosys_json_parser_test.dart`, `yosys_diagnostic_provider_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`test/integration/verilog_pipeline_test.dart`, real-yosys group) + `[Coverage: MANUAL]` (live open)
- [ ] ELK layout foundation (§3.3) — `buildElkInput` conversion, `ElkLayoutService` solve, isolate offload, disk cache, `LayoutException` mapping (28 tests); layout domain-type round-trips — `[Coverage: UNIT]` (`test/services/layout/elk_layout_service_test.dart`, `test/domain/models/layout/*_test.dart`) + `[Coverage: MANUAL]` (live flutter_js render, §9.9)
- [ ] Fixed pin faces (§3.3 step 4): on every cell, inputs on the left face and outputs on the right, feedback loops and wireless pins included, on desktop (elkrs) and web (elkjs): `[Coverage: UNIT]` (`elk_layout_service_test.dart`, `native_elk_solver_test.dart`, `native_elk_parity_test.dart`) + `[Coverage: MANUAL]` (serv_ice40 LUTs and flops)
- [ ] Theme system (§3.4) — dark/light are M3 with correct brightness and both derive from `NetcruxColors.brandSeed` (amber) — `[Coverage: UNIT]` (`test/core/theme/netcrux_theme_test.dart`) + `[Coverage: MANUAL]` (live brightness flip, §8)
- [ ] App-shell scaffolding (§3.5) — `NetcruxAction` labels/categories/bindings; `ShortcutManagerWidget` dispatch; command palette localized rows; `CliArgParser` intent + flag stripping; `FileOpenService` recent-files dedupe/cap — `[Coverage: UNIT/WIDGET]` (`netcrux_action_test.dart`, `action_category_test.dart`, `shortcut_bindings_provider_test.dart`, `shortcut_manager_widget_test.dart`, `command_palette_dialog_test.dart`, `cli_arg_parser_test.dart`, `file_open_service_test.dart`)
- [ ] Desktop hardening (§3.6) — 800×500 min window; macOS UTIs + Finder Open-With; `openAdaptive` modal (not a route); `DesktopMenuBar` platform Quit/About placement — `[Coverage: WIDGET]` (`settings_screen_test.dart`, `desktop_menu_bar_test.dart`, `workspace_opened_document_test.dart`, `incoming_document_service_test.dart`) + `[Coverage: STATIC]` (`macos_document_open_test.dart`) + `[Coverage: MANUAL]` (native window / UTIs / a real Finder double-click / trackpad-scroll-through-modal)

## Core Schematic Viewer

- [x] §4.2 Seeded-design journey — load (Yosys-free design-seed helper) →
      navigate hierarchy (row tap) → select cell → inspector renders
      instance/type/ports — `[Coverage: INTEGRATION_TEST]` via
      `integration_test/design/seeded_design_journey_test.dart` (macOS).
      Fixture guardrails: `[Coverage: UNIT]` via
      `test/fixtures/design_seed_fixture_sync_test.dart` + the
      `netlist_golden_test.dart` sweep (design `design_seed`).
- [x] §4.3 Elaboration cache — unchanged inputs re-elaborate from the LRU
      (same model instance + restored stderr, no Yosys spawn); touched
      source / changed Yosys version miss — `[Coverage: UNIT]` via
      `elaboration_cache_service_test.dart` +
      `loaded_netlist_provider_test.dart`. The <50 ms hit budget stays
      `[Coverage: MANUAL]` (a soft wall-clock budget, not asserted on shared runners).
- [ ] Schematic canvas navigation (§4.4) — Cmd/Ctrl+wheel zoom (10–1000% clamp), pan, `0` fit-all; double-click push-in / Backspace / Cmd+[ pop-out; clickable breadcrumb; three LOD bands; per-`CellKind` symbols — `[Coverage: UNIT/WIDGET/GOLDEN]` (`schematic_graph_builder_test.dart`, `schematic_painter_test.dart` + `schematic_painter_golden_test.dart`, `lod_band_test.dart`, `schematic_gesture_handler_test.dart`, `viewport_transform_notifier_test.dart`, `breadcrumb_bar_test.dart`, `symbol_painters_test.dart`, `hierarchy_tree_notifier_test.dart`) + `[Coverage: MANUAL]` (double-click push-in/pop-out gesture)
- [ ] Selection & inspector (§4.5) — click a cell/port/wire → hit-test priority (port→cell→boundary→wire) → inspector shows instance/type/kind/ports; Shift/Cmd multi-select; Esc clears — `[Coverage: UNIT/WIDGET]` (`selected_element_notifier_test.dart`, `selected_element_test.dart`, `selection_test.dart`, `schematic_hit_test_test.dart`, `element_path_test.dart`, `inspector_panel_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`integration_test/design/seeded_design_journey_test.dart`, §4.2)
- [ ] Canvas keyboard reach (§4.5 step 8) — Alt+Down/Up select cells and ports, Alt+Right/Left the cell's pins each followed by its net, Shift adds, Enter pushes in, Shift+F10 / Menu key opens the element menu; each selection is announced — `[Coverage: UNIT/WIDGET]` (`schematic_keyboard_navigator_test.dart`, `schematic_gesture_handler_keyboard_reach_test.dart`) + `[Coverage: MANUAL]` (spoken output under NVDA / VoiceOver; Pro cross-probe from the keyboard-opened menu)
- [ ] Hierarchy tree keyboard (§4.5 step 9) — one Tab stop on the selected scope; Up/Down/Home/End move, Right expands then enters, Left collapses then goes to the parent, Enter/Space select; focus ring visible; chevrons pointer-only; rows announce expanded/collapsed and selected — `[Coverage: WIDGET]` (`hierarchy_tree_panel_test.dart`, `hierarchy_tree_row_test.dart`, `screen_reader_test.dart`) + `[Coverage: MANUAL]` (spoken output under NVDA / VoiceOver)
- [ ] Canvas click latency (§4.5 steps 5–7) — a click selects the element **the moment the button is released**, with no ~300 ms dead zone; a quick second click is not swallowed as a double-click; press-and-drag pans without changing the selection; double-click still pushes into the scope — `[Coverage: WIDGET]` (`schematic_gesture_handler_test.dart` — "click selection" group: first-frame assertions, drag-to-cancel, double-click) + `[Coverage: MANUAL]` (perceived responsiveness on a real design)
- [ ] Design search (§4.6) — Cmd/Ctrl+F opens the dialog; substring/glob/regex match; a loaded design returns non-empty instance/cell/net hits (never a blanket "No results."); results and selection are scoped to the active tab; ArrowUp/ArrowDown move the highlight and Enter activates it; result navigates to owning scope — `[Coverage: UNIT]` (`design_search_service_test.dart`, `netcrux_action_test.dart` Cmd/Ctrl+F binding) + `[Coverage: WIDGET]` (`search_dialog_test.dart` — debounce, locale sweep, active-tab-container scoping, fixture-netlist hits over `design_seed.netlist.json`, keyboard activation) + `[Coverage: MANUAL]` (result-select navigation)
- [ ] One-step tracing (§4.7) — `]` fanout / `[` fanin dims off-cone, Esc clears; overlay is per-tab — `[Coverage: UNIT]` (`trace_service_test.dart`, `netcrux_tab_overrides_test.dart` overlay group) + `[Coverage: MANUAL]` (key→dim-path render)
- [ ] Esc clears a painted crossing (§4.7 step 3a, Pro build): one press clears the selection, the trace and a focused CDC or reset crossing, from the canvas or the rebindable Clear Selection / Overlay action, which a focused crossing alone enables; the crossing panes narrow to a signal filter and scroll a revealed row into view: `[Coverage: UNIT]` (`crossing_selection_lifecycle_test.dart`, `netcrux_action_descriptors_test.dart`, `active_tab_action_flags_provider_test.dart`) + `[Coverage: WIDGET]` (`schematic_gesture_handler_keyboard_reach_test.dart`, `crossing_pane_reveal_test.dart`) + `[Coverage: MANUAL]` (the paint going away)
- [ ] Zoom to Selection (§4.7 step 4) — `Z`, the toolbar button and Navigate > Zoom to Selection frame the selection plus everything a fanin / fanout trace highlights; greyed with nothing selected; returns to a cell picked in Search or the Hierarchy filter; `z` typed in a text field stays text — `[Coverage: UNIT]` (`selection_bounds_test.dart`, `zoom_to_selection_controller_test.dart`, `netcrux_action_descriptors_test.dart`, `shortcut_bindings_test.dart`) + `[Coverage: WIDGET]` (`shortcut_manager_widget_test.dart`) + `[Coverage: MANUAL]` (framing on a live canvas)
- [ ] Zoom In on every layout (§4.4 step 6) — Cmd/Ctrl+`=`, Cmd/Ctrl+`+` and Cmd/Ctrl+numpad `+` zoom in, including on a Swedish or German OS layout; rebinding Zoom In drops the extra forms — `[Coverage: UNIT/WIDGET]` (`shortcut_bindings_test.dart`, `shortcut_manager_widget_test.dart`) + `[Coverage: MANUAL]` (a real non-US layout)
- [ ] Canvas focus follows the pointer (§4.4 step 7) — after working in a panel, moving the pointer onto the schematic makes bare `=` / `-` / `0` work; a text field mid-edit keeps focus; any click (right-click included) on the canvas takes focus — `[Coverage: WIDGET]` (`schematic_gesture_handler_test.dart` "focus follows the pointer" group) + `[Coverage: MANUAL]`
- [ ] Hierarchy filter lists cells (§4.6 step 7) — placeholder reads **Filter scopes and cells…**; on serv_ice40 `add_cy` lists eleven cells (one `SB_DFF`, ten `SB_LUT4`) under `service`; clicking or Enter on a cell row selects and reveals it; Show more pages past 100; instances stay scope rows — `[Coverage: UNIT/WIDGET]` (`hierarchy_tree_panel_test.dart`, `hierarchy_leaf_row_test.dart`) + `[Coverage: MANUAL]` (canvas centering)
- [ ] Hierarchy cell rows keep their tail (§4.6 step 8): on serv_ice40 with a narrow panel, `add_cy` rows read `…alu.add_cy_r_SB_LUT4_I3_1` with the type beside them; hover shows the full name; a screen reader reads the full name once; the canvas cell label also keeps its end. `[Coverage: WIDGET]` (`hierarchy_leaf_row_test.dart`, `start_ellipsis_text_test.dart`) + `[Coverage: MANUAL]` (canvas label)
- [ ] Clicked wires, traces and Zoom to Selection on a flat netlist (§4.5 step 10, §4.7 step 5): on serv_ice40 click the I3 wire of `add_cy_r_SB_LUT4_I3_1`: the inspector names the net `servant.servile.cpu.alu.add_cy_r`; `[` lights the `SB_DFF` that drives it; `Z` frames that net and its cells, not the design. `[Coverage: WIDGET]` (`edge_id_agreement_test.dart`) + `[Coverage: MANUAL]`
- [ ] A session wire saved by an earlier build (§4.9 step 5): a wire record without `edgeIdScheme` selects its net. `[Coverage: UNIT]` (`session_controller_test.dart`)
- [ ] Export (§4.8) — PNG (`RenderRepaintBoundary`), SVG (`SvgExporter`, escaped text), JSON dump (Yosys-JSON round-trip) — `[Coverage: WIDGET]` (`schematic_export_controller_test.dart`, PNG guards) + `[Coverage: UNIT]` (`svg_exporter_test.dart`, `netlist_round_trip_test.dart`) + `[Coverage: MANUAL]` (live file write / visual fidelity)
- [ ] Session save/load (§4.9) — `.netcrux` versioned JSON; unknown field ignored, unknown version rejected with snackbar; re-opens as a tab and, once the design elaborates, lands on the saved scope, expanded rows, selection and camera (also into a tab showing another design) — `[Coverage: WIDGET]` (`schematic_fit_to_view_test.dart`) + `[Coverage: UNIT]` (`netcrux_session_test.dart`, `session_controller_test.dart`) + `[Coverage: INTEGRATION_TEST]` (full save→re-import UX round-trips scope/selection/camera, §4.1.3 — `session_export_round_trip_test.dart`)
- [ ] Settings screen (§4.10) — dual-pane master-detail (wide) collapses single-column (narrow); General/Appearance/Engines/Remote categories; theme mode persists live; custom Yosys path probe — `[Coverage: WIDGET]` (`settings_screen_test.dart`) + `[Coverage: UNIT]` (`app_settings_provider_test.dart`, `netcrux_settings_codec_test.dart`, `yosys_executable_provider_test.dart`, `cli_arg_parser_yosys_path_test.dart`) + `[Coverage: MANUAL]` (live `yosys -V` field)
- [ ] Auto-reload (§4.11) — edit tab A's source → only tab A re-elaborates (tab B untouched); AutoReloadMode auto/prompt/off honored — `[Coverage: UNIT]` (`source_file_watcher_per_tab_test.dart`) + `[Coverage: MANUAL]` (live file-watch → re-elaborate)
- [ ] Auto-reload (§4.11): open a design through the file dialog → no Reload prompt; edit and save it → the prompt appears. `[Coverage: UNIT]` (attribute-only change ignored, in `crux_file_watcher`) + `[Coverage: MANUAL]`
- [ ] Auto-reload (§4.11): AutoReloadMode prompt, two designs split → `touch` a source, Reload or leave the prompt, `touch` again → a prompt each time. `[Coverage: WIDGET]` (`source_reload_prompt_test.dart`) + `[Coverage: MANUAL]`
- [ ] Pin ties (§4.12): constant pins have a labelled stub, an undriven input an error-coloured stub with a ring, a declared-but-omitted port a bare pin; the inspector's **Tied to** row and Ports rows name each tie in every locale; serv_ice40 shows no undriven pins: `[Coverage: UNIT/WIDGET/GOLDEN]` (`declared_cell_ports_test.dart`, `schematic_graph_builder_test.dart`, `pin_tie_test.dart`, `pin_tie_text_test.dart`, `inspector_panel_test.dart`, `schematic_painter_golden_test.dart`, `native_elk_parity_test.dart`) + `[Coverage: MANUAL]` (the six colour presets; real designs, fixture `test/fixtures/netlist/serv_ice40/captured/serv_ice40.netlist.json.gz`)

## Workspace + Multi-Tab + Split-Pane

- [ ] Workspace auto-save on tab/pane mutations; `{appSupportDir}/workspace.json` exists after first launch — `[Coverage: INTEGRATION_TEST]` (`integration_test/workspace/restore_round_trip_test.dart`)
- [ ] Workspace restore on launch — open tabs, flush, re-read persisted `workspace.json`, verify identical state — `[Coverage: INTEGRATION_TEST]` (`integration_test/workspace/restore_round_trip_test.dart`)
- [ ] Named workspace save / load — `File → Save Workspace As…` writes a `.netcrux-workspace`, `File → Open Workspace…` round-trips it — `[Coverage: INTEGRATION_TEST]` (`integration_test/workspace/named_workspace_test.dart`); confirmation dialog `[Coverage: MANUAL]`
- [ ] Tab export — `File → Export Tab as Session…` produces a `.netcrux` that re-imports as a single tab — `[Coverage: INTEGRATION_TEST]` via `integration_test/session/session_export_round_trip_test.dart`
- [ ] Split-pane drag — drag a tab from one pane to the other; `WorkspaceTab.paneId` updates; the receiving pane becomes active — gesture `[Coverage: WIDGET — pending]`; mutation contract `[Coverage: INTEGRATION_TEST]` (`integration_test/workspace/split_pane_test.dart`)
- [ ] Split-pane keyboard — `Cmd/Ctrl+\` splits the active pane right; the active tab moves into the new pane — `[Coverage: INTEGRATION_TEST]` (`integration_test/workspace/split_pane_test.dart`, `splitPaneRight` path)
- [ ] Close Pane / Focus Other Pane / Move Tab to Other Pane reachable via command palette — `[Coverage: MANUAL]`
- [ ] CLI multi-file — `netcrux a.v b.v c.vhd` opens three separate tabs in the active pane — `[Coverage: INTEGRATION_TEST]` (`integration_test/tabs/cli_multi_file_test.dart`)
- [ ] CLI `--workspace <path>` opens a named workspace after a single confirmation — `[Coverage: WIDGET]` (parser); `[Coverage: MANUAL]` (confirmation dialog)
- [ ] Empty-canvas state — fresh launch / Reset Workspace renders the welcome content with recent lists + four primary actions — `[Coverage: WIDGET]`
- [ ] Loose-source top auto-selection — File → Open Source Files… (or `netcrux file.v`) with no project/top set still roots the hierarchy: Yosys runs `hierarchy -check -auto-top`, the elaborated design has a `(* top *)` module, and the left pane shows the tree (NOT "the elaborated design has no top module"). Regression check: open `test/fixtures/netlist/chain_10k/generated/chain_10k.v` — requires Yosys on PATH — `[Coverage: UNIT]` (`crux_yosys` `yosys_runner_test.dart` asserts `-auto-top`) + `[Coverage: MANUAL]` (live elaboration)
- [ ] Workspace shell (§4.1.12) — fresh launch shows the empty canvas **full-width with no side panel and no stray pane separator**; the per-tab IDE chrome (hierarchy / inspector / diagnostics) appears only once a tab is open — `[Coverage: WIDGET]` (`netcrux_ide_layout_test.dart`, `project_tab_content_test.dart`) + `[Coverage: MANUAL]` (no-separator visual)
- [ ] Panel-layout persistence (§4.1.12) — toggle inspector/diagnostics + resize hierarchy, relaunch, verify state restored from `netcrux.panelLayout.*`; panel visibility is shared across tabs — `[Coverage: UNIT]` (`panel_layout_state_test.dart`, `panel_layout_provider_test.dart`, `netcrux_settings_codec_test.dart`, `app_settings_provider_test.dart`) + `[Coverage: MANUAL]` (relaunch restore)
- [ ] Design status bar (§4.1.13) — open a real fixture (e.g. `vexriscv.v`); the per-tab bottom status bar reads `File: <name> · Top: <module> · <N> cells` (design-wide flattened count); an empty `+` tab reads "No design loaded"; the bar is per-tab (a second design's tab shows its own readout); narrowing the window scrolls the bar horizontally — `[Coverage: WIDGET]` (`netcrux_status_bar_test.dart`, `project_tab_content_test.dart`) + `[Coverage: MANUAL]` (live cell count vs real Yosys elaboration)
- [ ] Action toolbar (§4.1.14) — the toolbar above the tab strip shows Open Project / Open Source Files / Search / Jump to Top / Pop Out Scope / Fit to View; each button dispatches the same action as its menu/palette equivalent (tooltips show the localized action label); open-core only (no Pro buttons); visible on the empty canvas; scrolls horizontally when narrow — `[Coverage: WIDGET]` (`netcrux_toolbar_test.dart`, `widget_test.dart`) + `[Coverage: MANUAL]` (dispatch reaches downstream flows)
- [ ] CXP emitter survives panel toggles (§4.1.12) — hide the diagnostics drawer, change selection in the active tab, confirm peers still receive `NotifySelection`; background tabs do not broadcast — `[Coverage: MANUAL]`
- [ ] Missing-file recovery on restore — delete a tab's source file, relaunch, verify the schematic canvas shows `SchematicErrorView`'s localized "Elaboration failed" envelope (generic body + collapsed "Details") — never a raw `toString()` — `[Coverage: WIDGET]` (laid-out graph + hierarchy panel + `schematic_error_view_test.dart`) + `[Coverage: MANUAL]` (diagnostics fatal-error banner) — the deterministic missing-*engine* variant of this same fatal-error path (below) is now `[Coverage: INTEGRATION_TEST]`
- [ ] Missing-engine recovery (§4.1.7) — `which yosys` returns empty; open any tab; confirm the hierarchy panel shows the red `(!)` icon + `hierarchyEmptyElaborationFailed("Yosys is not available: …")`, the canvas shows `SchematicErrorView`'s localized envelope with the `elaborationErrorYosysUnavailable` guidance body (ARB key, **not** the raw exception text), and the diagnostics drawer (Cmd+3) shows the fatal-error banner — `[Coverage: WIDGET]` (hierarchy + canvas 5-locale sweep `schematic_error_view_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`integration_test/tabs/missing_engine_recovery_test.dart` — real app boot, pinned `yosysAvailabilityProvider`, asserts canvas + hierarchy + diagnostics-drawer surfaces all recover in one run)
- [ ] Cold-launch workspace hydration — write a synthetic `workspace.json` pointing at a real fixture, relaunch, confirm the tab opens AND the schematic renders within ~1s (no stuck "Open Project…" empty state, no race where `currentProjectProvider` stays empty after hydration) — `[Coverage: MANUAL]`
- [ ] Action dispatcher coverage — open the command palette (Cmd+Shift+P), run every entry, confirm none emit the legacy "is not yet implemented." snackbar (helper removed; reintroducing it would be a regression) — `[Coverage: MANUAL]`
- [ ] Keyboard-shortcut conflict resolution (§4.1.10) — rebinding an action onto another's chord shows asymmetric warnings (winner "Takes precedence over …", shadowed "Won't fire — shadowed by …"), a summary banner with the count, and at runtime the **remapped** action fires (deterministic, not enum-order) — `[Coverage: UNIT]` (`test/core/shortcuts/shortcut_conflicts_test.dart`) + `[Coverage: WIDGET]` (`test/core/shortcuts/shortcut_manager_widget_test.dart`, `test/features/settings/widgets/shortcuts_settings_section_test.dart`)
- [ ] Command palette always reachable (§4.1.11) — Open Command Palette appears under the View menu (not in the palette itself); after unbinding Cmd/Ctrl+Shift+P it is still reachable via View → Command Palette — `[Coverage: UNIT]` (`test/core/shortcuts/netcrux_action_descriptors_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`integration_test/command_palette/menu_reachability_test.dart` — real app boot, live unbind, dispatches via `DesktopMenuBar.onAction` the way the native View-menu item would, asserts the palette opens and excludes itself)
- [ ] Action enablement layer (§4.1.15) — empty-canvas walk greys every design/tab-dependent menu item + toolbar button, the palette omits them, and a design-gated chord is keyboard-inert; opening a design / selecting an element / running an analysis progressively enables the matching actions — `[Coverage: UNIT]` (`netcrux_action_descriptors_test.dart`, `active_tab_action_flags_provider_test.dart`) + `[Coverage: WIDGET]` (`action_surface_conformance_test.dart`, `shortcut_manager_widget_test.dart`) + `[Coverage: MANUAL]` (live walk)
- [ ] Upgrade-required dialog (§4.1.15) — post-beta (`kBetaPeriod = false`) at open-core tier, activating any PRO-badged action shows `NetcruxUpgradeDialog` (feature name + "NetCrux Pro" + tier badge) and dispatches nothing; during beta the dialog never appears; Pro/EDU tier activates normally — `[Coverage: WIDGET]` (`workspace_action_dispatcher_test.dart`, `workspace_screen_gating_test.dart`, `netcrux_upgrade_dialog_test.dart` incl. 4-locale sweep)
- [ ] CLI-open tab dedupe (§4.1.16) — launching with a project the restored workspace already holds **focuses** that tab instead of appending one; five relaunches leave one tab; the relative / trailing-separator / `..` / symlink / case spellings of the same path all hit the same tab; an *overlapping-but-unequal* source set and a project-vs-source-file view of the same file each stay their own tab; two blank "+" tabs stay independent — `[Coverage: UNIT]` (`test/services/workspace/netcrux_workspace_identity_test.dart`, incl. dedupe against a tab rehydrated from disk) + `[Coverage: INTEGRATION_TEST — pending]` (live CLI launch path) + `[Coverage: MANUAL]` (picker / recent-files / filelist re-open)
- [ ] Restore-tabs-on-launch gate (§4.1.17) — Settings → General shows **Restore tabs on launch** (default on); turning it **off** yields an empty canvas on the next launch while `{appSupportDir}/workspace.json` stays byte-identical on disk; turning it back **on** brings the same session back; the UI and `defaults write … flutter.settings.restoreTabsOnLaunch` write the same key; an unreadable settings store still restores and still renders (no launch hang) — `[Coverage: UNIT]` (`test/services/workspace/netcrux_workspace_restore_gate_test.dart`, `test/services/settings/netcrux_settings_codec_test.dart`) + `[Coverage: WIDGET]` (`test/features/settings/screens/settings_restore_tabs_tile_test.dart`, incl. 44 dp target + 4-locale sweep) + `[Coverage: MANUAL]` (real quit/relaunch)
- [ ] Restore **on** plus a CLI argument (§§4.1.16–4.1.17) — relaunching with one of the restored projects on the command line yields the restored tabs **plus exactly one** deduped CLI tab, focused; repeated five times it is still that same count — `[Coverage: MANUAL]`
- [ ] Reset a NetCrux session by hand (§4.1.17) — deleting `{appSupportDir}/workspace.json` is sufficient; NetCrux has no second `{appSupportDir}/<product>/workspace.json` project-registry document and no `sessions/` sidecars to re-seed it — `[Coverage: MANUAL]`
- [ ] Command palette keyboard execution (§4.1.18) — type a query, press **Enter**: the highlighted action runs and the palette closes; ↑/↓ move the highlight without moving the query caret; Escape closes the palette and nothing else — `[Coverage: WIDGET]` (`test/features/command_palette/widgets/command_palette_enter_test.dart` — drives Enter as a `TextInputAction.done` on the text-input channel, the delivery path `tester.sendKeyEvent` cannot reproduce and the one the shipped defect broke; incl. 4-locale sweep) + `[Coverage: MANUAL]` (keyboard-only drive in a release build)
- [ ] Shipped `examples/` open from a clean checkout (§4.1.19) — from a working directory that is **not** the repo root, **File → Open Project…** on `examples/adder4/adder4.netcrux-project` and `examples/cdc-capture/cdc-capture.netcrux-project` each render a schematic; project-relative source paths are anchored to the project file's directory (not the process CWD) and the project's `defines` / `includePaths` / `extraYosysCommands` survive the open; a positional `.netcrux-project` CLI arg opens as a project, not as HDL — `[Coverage: UNIT]` (`test/examples/examples_test.dart`, `test/services/project/netcrux_project_path_resolver_test.dart`, `test/core/cli/cli_arg_parser_test.dart`) + `[Coverage: MANUAL]` (real Yosys, non-repo CWD)
- [ ] Examples degrade cleanly with no Yosys (§4.1.19) — with `yosys` off `PATH`, both examples still open a tab and show "Elaboration failed" / "Yosys was not found on your PATH…" on the canvas plus the `Yosys not found` status-bar segment; nothing looks silently broken — `[Coverage: MANUAL]`
- [ ] Locale sweep on empty-canvas + tab bar strings — switch en / zh_CN / ja / ko via Settings; verify no overflow + correct labels — `[Coverage: WIDGET]`
- [ ] Per-tab auto-reload — change a source file in tab A; verify only tab A re-elaborates (tab B's diagnostics drawer untouched) — `[Coverage: WIDGET]` (per-tab isolation) + `[Coverage: MANUAL]` (live file watch)
- [ ] Multi-window "Move to New Window" menu item visible but disabled (gated on `kMultiWindowAvailable` — Pro tier, future) — `[Coverage: WIDGET — pending]`

## Project Files, VHDL, Web Read-Only

**Web schematic viewer — client-side elkjs layout (§5.1)**
- [ ] `?json=<url>` and the start screen's **Open Netlist JSON…** load a Yosys netlist JSON, populate the hierarchy, and **auto-select the top module**; `#scope=` / `#sig=` land; a failed fetch explains itself — `[Coverage: WIDGET]` (`workspace_web_launch_test.dart`) + `[Coverage: UNIT]` (`web_deep_link_test.dart`) + `[Coverage: MANUAL]` (§5.1 steps 1–6)
- [ ] In a real browser the pipeline reads netlists in place and no CXP server starts or resolves its discovery directory — `[Coverage: CI]` (`tool/run_web_tests.sh`: `prebuilt_netlist_loader_web_test.dart`, `cxp_server_provider_web_test.dart`)
- [ ] In a real browser a tab's location is keyed verbatim and case-sensitively, and a project opens under no organization policy without an override — `[Coverage: CI]` (`tool/run_web_tests.sh`: `netcrux_workspace_codec_web_test.dart`, `audit_emission_web_test.dart`)
- [ ] The browser build hides every action that needs a file system, subprocess or socket, and every Pro action, on the toolbar, palette and keyboard — `[Coverage: UNIT]` (`netcrux_action_descriptors_test.dart`, `shortcut_manager_widget_test.dart`) + `[Coverage: WIDGET]` (`action_surface_conformance_test.dart`) + `[Coverage: MANUAL]` (§5.1 step 1)
- [ ] Selecting a scope on web **lays out client-side and paints a schematic** (elkjs runs natively via `elk_web_solver_web.dart`; no isolate, no flutter_js) — this is the new behavior; pre-change it threw `UnsupportedError` (Isolate.spawn) — `[Coverage: MANUAL]` (§5.1 steps 2–3, 5) — **automation gap: no Chrome-headless harness in netcrux yet**
- [ ] Web build compiles the `dart:js_interop` solver under dart2js — `[Coverage: CI]` (`flutter build web` / `build-web`)
- [ ] Off-web resolves the stub (`kElkWebSolverAvailable == false`), so desktop keeps the isolate path — `[Coverage: UNIT]` (`elk_web_solver_stub_test.dart`)
- [ ] Desktop layout pipeline unchanged (isolate offload, mem/disk caches, `LayoutException` mapping) — `[Coverage: UNIT]` (`elk_layout_service_test.dart`, 28 tests)
- [ ] Malformed netlist / elkjs failure surfaces a `LayoutException` in the canvas error view; strict-CSP hosts need `worker-src blob:` — `[Coverage: MANUAL]` (§5.1 diagnostics + edge cases)

**Project / VHDL / diagnostics (§5.2–§5.7)**
- [ ] `.netcrux-project` file (§5.2) — sources/top/defines/includes; forward-compat (unknown field ignore, unknown version reject); opens via `golden_v1.netcrux-project` (no command writes one; the writer's pretty-print and atomic write are unit-only) — `[Coverage: UNIT]` (`netcrux_project_test.dart`, `netcrux_project_file_test.dart`) + `[Coverage: MANUAL]` (live open+elaborate)
- [ ] `.f` filelist import (§5.3) — sources / `+define+` / `+incdir+` / recursive `-f` / comments / `$VAR` expansion; `FilelistCycleException` + `FilelistNotFoundException`; `readAsProject`; Cmd/Ctrl+Shift+I — `[Coverage: UNIT]` (`filelist_reader_test.dart`) + `[Coverage: WIDGET]` (import action dispatch)
- [ ] VHDL via `ghdl --synth` (§5.4) — ghdl lowers the VHDL to Verilog in a separate process; the Yosys script reads Verilog and loads no `plugin -i ghdl`; a ghdl failure surfaces through the non-zero-exit envelope; `BundledBinaryResolver` via `NETCRUX_BUNDLED_BIN_DIR` — `[Coverage: UNIT]` (`mixed_language_script_test.dart`, `bundled_binary_resolver_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`test/integration/vhdl_pipeline_test.dart`, skipped w/o ghdl) + `[Coverage: MANUAL]` (live host)
- [ ] Mixed-language designs (§5.5) — Verilog+VHDL in one project; extension auto-detect; ghdl lowers only the VHDL files; Yosys reads the Verilog sources and the lowered VHDL before `hierarchy` — `[Coverage: UNIT]` (`mixed_language_script_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`test/integration/mixed_pipeline_test.dart`, skipped w/o ghdl) + `[Coverage: MANUAL]` (live host)
- [ ] JSON streaming parser (§5.6) — brace-depth per-module decode, bounded memory, `CancellationToken`, cross-parser equivalence; default in the load pipeline; malformed → typed `YosysJsonParseException` with module name — `[Coverage: UNIT]` (`streaming_yosys_json_reader_test.dart`, `loaded_netlist_provider_test.dart`) + `[Coverage: FUZZ]` (`yosys_json_fuzz_test.dart` + `malformed/`)
- [ ] Yosys diagnostic surfacing (§5.7) — Tab Diagnostics drawer (Cmd+3) lists severity + `file:line`; severity chips (empty-set → reset all-on); per-row copy + Copy Report; warnings appear on successful runs too — `[Coverage: UNIT]` (`elaboration_diagnostics_provider_test.dart`) + `[Coverage: WIDGET]` (`tab_diagnostics_drawer_test.dart`) + `[Coverage: MANUAL]` (live Yosys warnings)
- [ ] Diagnostics drawer two-tab isolation (§5.7) — elaborate in tab A, open a second tab, confirm each drawer shows only its own run and that narrowing tab A's severity chips leaves tab B all-on — `[Coverage: UNIT]` (`per_tab_elaboration_diagnostics_scope_test.dart`) + `[Coverage: STATIC]` (`per_tab_provider_scope_leak_test.dart`) + `[Coverage: MANUAL]` (live two-tab run)
- [ ] Opening a design as what it is (§5.8) — a single `.json` netlist renders with Yosys absent; a `<design>.crux-project` (or the design directory holding it) opens its netlist, or all of its sources with `design.top`; an unusable manifest, or a directory with no manifest or several, explains itself in the UI language; a legacy bare `.crux-project` opens with one rename notice; `--session`, a positional `.netcrux` and Open Project… on a session all open the session's design — `[Coverage: UNIT]` (`loaded_netlist_provider_test.dart`, `prebuilt_netlist_loader_test.dart`, `cli_arg_parser_test.dart`, `crux_project_resolution_test.dart`) + `[Coverage: WIDGET]` (`workspace_open_design_test.dart`) + `[Coverage: MANUAL]` (live multi-source manifest)

## Cross-Probing & CXP

- [ ] CXP server lifecycle (§6.1) — server binds default port 54323, writes/removes manifest in the **suite-shared** `crux/cxp/peers/` directory (per-user app-data root, NOT the per-app container; heartbeat-refreshed every ~30 s), status row in cross-probe panel reflects enabled/disabled state from Settings → CXP Cross-Probe
- [ ] **Mutual-connectivity regression:** two suite apps on one machine mutually list each other as connected peers within ~5 s and stay listed past 5 minutes — `[Coverage: AUTOMATED]` (`netcrux_cxp_server_test.dart` "two servers sharing one manifest directory..."; `crux_cxp` `peer_connectivity_test.dart`) + real two-app flow `[Coverage: MANUAL]` — `[Coverage: INTEGRATION_TEST]` (`integration_test/remote_control/cxp_server_lifecycle_test.dart`: boot-start + settings-toggle teardown/restart) + `[Coverage: MANUAL]` (panel status row + on-disk manifest)
- [ ] **X1 connector-link routing (§6.1):** `CxpPeerConnector(server: server)` merges link-only traffic into the dispatch stream, attaches the link as a reply route, and auto-subscribes it — a peer reachable only through the connector's own outbound link (never dials us back) can still send us a request, get an ack, and receive our broadcasts — `[Coverage: AUTOMATED]` (`cxp_connector_link_test.dart`, both cases; regression-verified by temporarily dropping `server:` and observing the test fail)
- [ ] notify_selection emission (§6.2) — cell / port / wire / boundary-port selections each broadcast the correct `ElementKind` with the canonical path. Clearing the selection emits nothing — `[Coverage: INTEGRATION_TEST]` (`integration_test/remote_control/notify_selection_emission_test.dart`: real app + raw subscribed peer + cell selection)
- [ ] request_highlight receive (§6.3) — instance / port / net update the active tab's selection; scope navigates the hierarchy; unknown scope returns `honored: false` — `[Coverage: INTEGRATION_TEST]` (`integration_test/remote_control/request_highlight_navigation_test.dart`: instance → inspector, scope → hierarchy navigation, through the real `CxpInboundListener` wiring)
- [ ] request_open_source (§6.4) — happy path opens the configured editor at file:line; empty command and non-existent executable both ack `honored: false`.
- [ ] Cross-probe panel (§6.5) — peer discovery appears within ~2 s, drops within ~2 s on peer departure; event log captures inbound + presence events — `[Coverage: INTEGRATION_TEST]` (`integration_test/remote_control/cross_probe_panel_discovery_test.dart`: real two-peer manifest exchange via a second `NetcruxCxpServer`, panel peer-list + event-log presence/message assertions)
- [ ] **Send selection to a peer (§6.5.1)** — with a cell selected, pressing Send selection on a peer row transmits that element's canonical path (the Copy Path string), kind `instance`, display name = cell id, plus `netcrux.scope_path` metadata; a wire selection transmits kind `net` / `net_<id>`. Empty selection, unloaded design, stopped server, and a vanished peer each report their own snackbar and transmit nothing (except the vanished-peer case, which attempts the send). Switching tabs and pressing again sends the **new** active tab's selection — `[Coverage: UNIT]` (`cross_probe_panel_test.dart` send-selection group, `cxp_selection_resolver_test.dart`) + `[Coverage: MANUAL]` (live tab switch; peer disappearing mid-flight)
- [ ] **Regression:** Send selection no longer transmits the hardcoded `top:cell` placeholder it once sent — confirm the received path matches the actual selection.
- [ ] **Unreachable-peer indicator (§6.5.2)** — a discovered-but-undialable peer (stale/wrong-port manifest, hard-killed peer) surfaces a persistent "Couldn't reach <peer>" warning row below the Peers list within ~5 s; the row clears when the peer becomes reachable or its manifest is removed; no row/icon when every peer is reachable — `[Coverage: UNIT]` (`cxp_dial_failures_provider_test.dart`, `cross_probe_panel_test.dart` unreachable-row group, `netcrux_cxp_server_test.dart` dial-failure surface getters) + `[Coverage: MANUAL]` (lingering manifest + live recovery)
- [ ] Locale sweep (§6.6) — panel + Settings → CXP Cross-Probe render in en, zh_CN, zh, ja, ko without exceptions.
- [ ] crux_cxp conformance suite re-runs against `NetcruxCxpServer` (handshake, subscribe + broadcast, sendTo, error response on unknown kind, clean disconnect) via `test/services/remote/cxp/netcrux_cxp_server_conformance_test.dart`.

## Pro extension-point seams (Open Core)

- [ ] `ConeOfInfluenceService` open-core default (§7.1) — `NoopConeOfInfluenceService` returns `TraceOverlay.empty`; provider override semantics covered in `test/services/schematic/cone_of_influence_service_provider_test.dart`. `[Coverage: INTEGRATION_TEST]` (`integration_test/schematic/cone_of_influence_seam_test.dart`, no-op dispatch against a seeded design).
- [ ] `NetcruxAction` cone-of-influence actions (§7.2) — three new entries (`showConeOfInfluenceFanin`, `showConeOfInfluenceFanout`, `clearConeOfInfluence`) appear in the command palette in all five locales. `requiredTier` returns `LicenseTier.pro` for the trace actions and `openCore` for the clear action.
- [ ] **Clear / dismiss actions carry no PRO badge** — Clear Overlay, Clear Cone of Influence, Clear X-Trace, Clear Comparison Netlist, Clear FSM Selection, Clear CDC Selection, Clear Reset Selection, Clear Activity Coloring all render unbadged in the command palette and unsuffixed in the native menu bar, and activate at open-core tier post-beta. (`clearComparisonNetlist` was mis-declared Pro-tier while the dispatcher never gated it, so it badged an action a licence could not unlock.) — `[Coverage: UNIT]` (`netcrux_action_test.dart` "every clear / dismiss action is Open Core", `workspace_action_dispatch_table_test.dart`)
- [ ] Action-surface tier badges (§7.2) — the command palette renders a `NetCruxFeatureTierBadge` on Pro/ENT rows and none on open-core rows (`CommandPaletteDialog.trailingBuilder`); the native menu bar appends a localized `" (PRO)"` / `" (ENT)"` suffix (`tierLabelSuffix` + `menuItemTierSuffix` ARB ×5 locales) and nothing for open-core. Both read the same `requiredTier`. `[Coverage: UNIT]` `action_tier_label_test.dart`; `[Coverage: WIDGET]` (5-locale sweep) `command_palette_dialog_test.dart` + `desktop_menu_bar_test.dart` (macOS + Windows + Linux). The earlier `crux_command_palette` `trailingFor` block was stale — the slot already ships.
- [ ] Pro actions in an open-core build (§7.2) — with no Pro overlay, every Pro action (palette, menu, the inspector's badged **Go to source**, Show Bookmarks / Annotations Panel) shows "<action> requires NetCrux Pro." instead of doing nothing; post-beta at the open-core tier the upgrade dialog comes first — `[Coverage: WIDGET]` `pro_action_gate_test.dart`, `workspace_screen_gating_test.dart`, `inspector_panel_test.dart`
- [ ] License-badge wiring (§7.3) — `NetcruxLicenseBadgeStrings(L10N.of(context))` resolves the six `tierBadge*` ARB keys in every locale; `NetCruxFeatureTierBadge` / `NetcruxEducationalBadge` wrappers render the correct chip per tier.
- [ ] `XTraceService` open-core default (§7.4) — `NoopXTraceService` returns `XTraceResult.empty`; provider override semantics covered in `test/services/schematic/x_trace_service_provider_test.dart`; `XTraceResultNotifier` set / clear covered in `test/features/viewer/providers/x_trace_result_notifier_test.dart`. `[Coverage: INTEGRATION_TEST]` (`integration_test/schematic/x_trace_seam_test.dart`, no-op dispatch against a seeded design).
- [ ] X-trace origin reasons (§7.4): a `foundOrigin` result's `originReason` / `originPortId` render as "Origin reached on this path: <reason>" in all five locales, a reason on any other termination is ignored, and `SchematicCell.initValue` carries the `init` attribute of the net a cell drives. `[Coverage: UNIT_TEST]` via `test/features/viewer/widgets/x_trace_result_panel_test.dart`, `test/domain/interfaces/x_trace_service_test.dart` and `test/services/schematic/schematic_graph_builder_test.dart`.
- [ ] `NetcruxAction` X-trace actions (§7.4) — `showXTrace`, `showXTracePanel` and `clearXTrace` appear in the command palette / menu bar (all five locales), and `showXTracePanel` opens `XTraceResultPanel` on its empty state — `[Coverage: UNIT_TEST]` via `test/core/shortcuts/netcrux_action_descriptors_test.dart`. `requiredTier` returns `LicenseTier.pro` for `showXTrace` and `LicenseTier.openCore` for the panel / clear actions.
- [ ] FSM bubble diagram pane empty state: the hint names the schematic context-menu entry "Detect FSM for This Register" and quotes the palette action "Run FSM Detection Across Design…" verbatim in all five locales, and wraps inside the pane rather than running past its right edge. `[Coverage: UNIT_TEST]` via `test/features/fsm/widgets/fsm_bubble_diagram_pane_test.dart` (wording); the narrow-dock wrap is covered by the overlay's dock tests.
- [ ] `BookmarkAnnotationStore` open-core default (§7.5) — `NoopBookmarkAnnotationStore` ignores writes and always returns `BookmarkAnnotationSnapshot.empty`; provider override semantics covered in `test/services/session/bookmark_annotation_store_provider_test.dart`. `[Coverage: INTEGRATION_TEST]` (`integration_test/session/bookmark_annotation_seam_test.dart`, no-op dispatch against a seeded design).
- [ ] `Bookmark` + `Annotation` domain-model round-trip (§7.5) — every `BookmarkTargetKind` value round-trips through JSON; malformed entries return `null` from `fromJson`; covered by `test/domain/models/{bookmark,annotation}_test.dart`.
- [ ] `NetcruxSession` carries `bookmarks` + `annotations` (§7.5) — fields default to empty lists; toJson omits keys when empty; fromJson tolerates missing keys (compatibility with sessions from builds that predate bookmarks) and silently drops malformed entries. Covered by `test/domain/models/session/netcrux_session_test.dart`.
- [ ] `NetcruxAction` bookmark / annotation actions (§7.5) — four new entries (`addBookmark`, `showBookmarksPanel`, `addAnnotation`, `showAnnotationsPanel`) appear in the command palette in all five locales. `requiredTier` returns `LicenseTier.pro` for the add actions and `LicenseTier.openCore` for the panel-toggle actions.
- [ ] `schematicContextMenuExtensionsProvider` open-core default (§7.6) — resolves to an empty `List<SchematicContextMenuExtensionBuilder>`; the schematic context menu shows only built-in entries; provider override semantics covered in `test/features/viewer/widgets/schematic_context_menu_extension_test.dart`.
- [ ] `CustomCellSymbolRegistry` open-core default (§7.7) — `NoopCustomCellSymbolRegistry` has an empty snapshot, null lookups, silent mutations, never-emitting change stream; provider override semantics covered in `test/services/custom_cell_symbols/custom_cell_symbol_registry_provider_test.dart`. `[Coverage: UNIT]` + `[Coverage: INTEGRATION_TEST]` (`integration_test/custom_cell_symbols/custom_cell_symbol_seam_test.dart`, no-op dispatch against a seeded design's real module type).
- [ ] `CustomCellSymbol` + `PortAnchor` + `CustomCellSymbolMatch` domain-model round-trip (§7.7) — every field round-trips through JSON; malformed entries fall back to defaults; covered by `test/domain/models/custom_cell_symbol/*_test.dart`. `[Coverage: UNIT]`
- [ ] `cellBodyPainterFactoryProvider` open-core default (§7.7) — `defaultCellBodyPainterFactory` returns `painterFor(cell.kind)` for every cell; provider override semantics covered in `test/features/viewer/symbols/cell_body_painter_factory_test.dart`. `[Coverage: UNIT]`
- [ ] `NetcruxAction` custom-cell-symbol actions (§7.7) — four new entries (`openSymbolManager`, `importSymbolFromSvg`, `editSymbolForCurrentInstance`, `removeSymbolForCurrentInstance`) appear in the command palette in all five locales. All four return `LicenseTier.pro` from `requiredTier`. `[Coverage: WIDGET]` (palette + locale) `[Coverage: UNIT]` (tier mapping)
- [ ] Custom-cell-symbol opener seams (§7.7) — `openSymbolManagerOpenerProvider` / `importSymbolFromSvgOpenerProvider` / `editSymbolForCurrentInstanceOpenerProvider` / `removeSymbolForCurrentInstanceOpenerProvider` default to no-ops on open-core; dispatch invokes without throwing. Covered by `test/services/custom_cell_symbols/custom_cell_symbol_openers_test.dart`. `[Coverage: WIDGET]`
- [ ] Symbol-shaped layout (§7.7): a cell with a custom symbol gets a `FIXED_POS` node of the drawing's aspect with each anchored pin on its anchor's face at the anchor's position; crowded anchors spread to a 10-unit pitch; designs without symbols keep a byte-identical ELK input (parity fingerprints unchanged). Covered by `test/services/layout/symbol_cell_layout_test.dart` (native, plus elkjs on macOS) and `test/services/custom_cell_symbols/cell_symbol_geometry_provider_test.dart`. `[Coverage: UNIT]`
- [ ] Symbol cell label and pin names (§7.7): at the detail band the instance name sits outside the drawing (below, or above when blocked), and only pins an anchor names exactly are labelled, inside the drawing on their face; nothing on ordinary cells or in the mid and overview bands. Covered by `test/features/viewer/rendering/schematic_symbol_cell_test.dart` and `test/features/project/providers/current_laid_out_graph_provider_test.dart`. `[Coverage: WIDGET]`
- [ ] Crossing overlay paints the crossing net (§7.8): `SchematicCrossingOverlay.netIds` strokes every laid-out strand of the crossing net in the severity colour; default empty, so older overlays paint as before. Pro, on cdc-capture: run CDC, select `sample_a`; expected: its source and capture registers and the 8 bus wires paint red. `[Coverage: UNIT]` (`test/features/viewer/rendering/schematic_painter_test.dart`, `test/services/schematic/schematic_crossing_overlay_provider_test.dart`)
- [ ] Diff pane seam (§7.9): a generated row reads as type plus `file:line` with the full name in its tooltip, and a generated net as type, `file:line` and `(pin)`, with `$20` path escapes decoded; a row click and the row's Show in Schematic button each select that row and hand over its own change; the button is an icon that stays inside the row at any width, with its label only from 400 px; an Added row's button is disabled with the comparison-only tooltip; Removed / Modified / Unchanged rows select their element through the exact-name `AnalysisSelectionProbe` methods; the footer arrows walk the list in display order. `[Coverage: UNIT]` `[Coverage: WIDGET]` (`test/features/diff/widgets/diff_pane_test.dart`, `test/features/diff/widgets/diff_row_label_test.dart`, `test/domain/models/diff/diff_element_address_test.dart`, `test/features/viewer/services/analysis_selection_probe_test.dart`)
- [ ] Source pane seam (§7.10): `AnalysisPanelKind.source` docks as a closable **Source** tab labelled in all five locales; `SourcePane` scrolls a line longer than the pane sideways inside the code view and leaves short lines unscrolled; a remount with no pending scroll centres the highlighted line again. `[Coverage: WIDGET]` (`test/features/source_pane/widgets/source_pane_test.dart`, `test/features/workspace/widgets/netcrux_right_dock_test.dart`)
- [ ] Switching-activity colors seam (§7.11): `NetActivity.isClock` round-trips; `ActivityNormalization.rank` is the default; every `ActivityColorScheme` ramp, per canvas brightness, is at least 3:1 on all six presets' canvas with the coldest color clear of an uncolored wire; `clockColor` is apart from every ramp; the pane's legend and row bars match `colorForNet`; while the coloring is shown an uncolored wire fades to 25 %. Pro, on `fsm_lock` + `fsm_pass.vcd`: `clk` magenta and tagged **Clock**, the data nets in three distinct colors. `[Coverage: UNIT]` `[Coverage: WIDGET]` (`test/domain/models/activity/activity_color_scheme_test.dart`, `test/features/activity/widgets/activity_heatmap_pane_test.dart`, `test/features/viewer/rendering/schematic_painter_test.dart`)

## Color Theming & Customization (suite-wide)

See VERIFICATION_GUIDE.md §8 for step-by-step instructions.

- [ ] Picking `WaveCrux Light` flips MaterialApp brightness to light: scaffold, AppBar, panel surfaces, settings dialog all visibly light — `[Coverage: INTEGRATION_TEST]` (`integration_test/theme/theme_switch_test.dart`, themeMode flip) + `[Coverage: MANUAL]` (surface repaint)
- [ ] Picking `WaveCrux Dark` from light state flips brightness back to dark — `[Coverage: INTEGRATION_TEST]` (`integration_test/theme/theme_switch_test.dart`) + `[Coverage: MANUAL]` (surface repaint)
- [ ] Picking `Solarized Dark` re-tints toolbar / scaffold / panel backgrounds with Solarized hues (NOT default Material-3 dark) — `[Coverage: MANUAL]`
- [ ] Picking `Oscilloscope` re-tints chrome with phosphor-green-on-black — `[Coverage: MANUAL]`
- [ ] Active preset survives an app restart (round-trips through `AppSettings.core.activeThemeName`) — `[Coverage: MANUAL]`
- [ ] Per-token chrome override: edit `toolbar.background`, observe immediate repaint, reset clears it — `[Coverage: MANUAL]`
- [ ] Import `.crux-theme.json` via Theme pack browser: pack appears in installed list, Activate applies tokens — `[Coverage: MANUAL]`
- [ ] Export active theme: `.crux-theme.json` contains expected keys (schemaVersion, id, displayName, brightness, tokens) — `[Coverage: AUTOMATED]` (`crux_theme` package suite)
- [ ] No RenderFlex overflow in Settings → Appearance at 320 dp width — `[Coverage: MANUAL]`
- [ ] No exception in en / zh_CN / ja / ko locale sweeps for Settings → Appearance — `[Coverage: MANUAL]`

## Robustness & Performance

- [x] **Killable Yosys subprocess.** `crux_yosys` spawns via `Process.start`; a real 30 s sleeper is `SIGKILL`'d under a 300 ms budget; `YosysRunTimeout`/`YosysRunCancelled` mapping + temp cleanup on kill (§9.1) — `[Coverage: UNIT_TEST]` via `crux_yosys` `process_runner_timeout_test.dart` + `yosys_runner_test.dart`.
- [x] **Pipeline timeout/cancel wiring + budget math.** Size-aware policy (floor/cap/scaling); pipeline surfaces `YosysTimeoutException`; cancel → empty (§9.1) — `[Coverage: UNIT_TEST]` via `elaboration_timeout_provider_test.dart` + `yosys_runner_timeout_test.dart`.
- [x] **Elaboration failures reach the user as a localized envelope, never a raw error.** `SchematicErrorView` maps each `LoadedNetlistException.kind` (yosysUnavailable / timeout / nonZeroExit) to an ARB body under the localized "Elaboration failed" title; unclassified errors (incl. `LayoutException`) get the generic envelope; raw text lives only in the collapsed "Details" expander — the exception class name never renders (both classified and unclassified errors). — `[Coverage: WIDGET]` 5-locale sweep via `schematic_error_view_test.dart`.
- [x] **Streaming Yosys-JSON reader never leaks a raw error.** Nested type error → typed `YosysJsonParseException` with the module name; mutation-anchored on `nested_type_error` (§9.2) — `[Coverage: FUZZ]` via `yosys_json_fuzz_test.dart` + the `test/fixtures/netlist/malformed/` corpus.
- [x] **Workspace codec only throws `FormatException`.** Per-field type violations + seeded truncation/mutation (§9.2) — `[Coverage: FUZZ]` via `workspace_codec_fuzz_test.dart`.
- [ ] **Bounded-elaboration manual smoke.** Wedged Yosys / pathological RTL → timed-out error within budget, no orphaned process or temp file (§9.1) — `[Coverage: MANUAL]`.
- [x] **Yosys-free golden sweep.** Each committed design's parsed golden matches its snapshot; `chain_10k == 10000` cells; corpus non-empty; mutation-anchored on a dropped cell (§9.3) — `[Coverage: GOLDEN]` via `netlist_golden_test.dart`.
- [x] **Captured tier.** `picorv32` (ISC) real-core netlist + golden + PROVENANCE; golden sweep + license/companion guards discover `captured/` (§9.3) — `[Coverage: GOLDEN + STATIC]`.
- [ ] **Large real-design live render (§9.9).** Open `test/fixtures/netlist/picorv32/captured/picorv32.v` (Yosys on PATH); hierarchy roots at `picorv32_wb`; click into the `picorv32` scope → the dense ~1 599-cell core **auto-fits to view** (whole schematic centered, not a corner); `0` re-fits; pan/zoom explores. First navigation shows an **progress bar + "Laying out the schematic… (N cells)" + elapsed time** (not a frozen window) for ~4–5 s while the ELK solve runs on a background isolate; cached after — `[Coverage: MANUAL]` (live render) + `[Coverage: GOLDEN + STATIC]` (parse + fixture guards).
- [ ] **Layout isolate offload (§9.9).** The elkjs solve runs off the UI isolate; production path proven against real flutter_js + the elk bundle with warm reuse; progress message resolves in all 5 locales — `[Coverage: UNIT]` (`elk_layout_service_test.dart` isolate-offload group) + `[Coverage: WIDGET/UNIT]` (`project_tab_content_test.dart` progress-message plural + locale).
- [ ] **Layout cache (§9.9).** In-memory (A→B→A instant in-session) + disk-backed (re-open across app restarts skips the solve; `layout-cache/*.json.gz` appears under app-support) — `[Coverage: UNIT]` (`elk_layout_service_test.dart` cache group: mem-hit, cold-service disk-hit, `FileLayoutDiskCache` round-trip/prune) + `[Coverage: MANUAL]` (cross-restart re-open).
- [ ] **VexRiscv hierarchical large render (§9.9).** Open `test/fixtures/netlist/vexriscv/captured/vexriscv.v` (Yosys on PATH); hierarchy auto-roots at `VexRiscv` (~1 463-cell pipeline); navigate into `DataCache` / `InstructionCache` scopes; each auto-fits + renders; second open is cache-fast — `[Coverage: MANUAL]` (live render) + `[Coverage: STATIC]` (captured license/layout guards).
- [ ] **Large-scope render plumbing (§9.9).** Fit-to-view + zoom-floor + edge-cap that make the above work — `[Coverage: UNIT]` (`viewport_transform_notifier_test.dart` fitToBounds incl. sub-0.1 zoom; `schematic_painter_test.dart` minZoom 0.01; `elk_layout_service_test.dart` high-fanout net skip) + `[Coverage: WIDGET]` (`schematic_gesture_handler_test.dart` 0 = Fit-All).
- [x] **Performance baseline pass (§9.3).** 1M parse 4.8 s ✓ / RSS ~4.3 GB ⚠, Yosys startup 5–10 ms ✓ — `[Coverage: BENCH]` (single machine; in-app GPU/render rows pending).
- [x] **Corrupt workspace recovers + quarantines + notifies.** Truncated/garbage/non-object/version-skewed `workspace.json` → empty workspace + `.corrupt-*` sibling + localized notice; healthy/missing → no recovery (§9.4) — `[Coverage: UNIT_TEST + INTEGRATION]` via `workspace_corruption_recovery_test.dart` + `workspace_restore_from_corruption_pipeline_test.dart`.
- [x] **Corpus + subprocess static guards.** Layout / companion / captured-license / no-unbounded-subprocess; all five mutations verified red (§9.5) — `[Coverage: STATIC]` via `test/static/`.
- [ ] **Stress-ladder and workspace-restore perf budgets.** 10K elaborate+render &lt; 3 s; workspace restore &lt; 200 ms — recorded in the baseline pass — `[Coverage: MANUAL]`.
- [x] **Whole-scope render golden.** Fixed three-cell design at the LOD detail/mid boundary; mutation-anchored on the LOD threshold (§9.6) — `[Coverage: GOLDEN]` via `schematic_painter_golden_test.dart`. Benchmarks recorded via `test/benchmarks/` (RUN_BENCHMARKS).
- [x] **COI/X-trace isolate-offload seam.** Open-core `computeAsync`/`traceAsync` holds a 100K scope; Pro size-gated `Isolate.run` offload with inline/async parity (§9.7) — `[Coverage: UNIT_TEST]` via `coi_scale_test.dart` + Pro `isolate_coi_service_test.dart`. (Full 100K no-jank relies on the Pro zero-copy projection.)
- [x] **CXP robustness.** Bind failure degrades gracefully (no launch crash); malformed inbound → error reply + server alive (unknown-verb mutation-anchored, plus a malformed-payload-of-a-known-kind case — a syntactically valid `hello` envelope whose `identity` isn't an object yields `malformed_payload`, not a crash); stale manifest pruned (§9.8) — `[Coverage: UNIT_TEST + FUZZ]` via `cxp_bind_failure_test` / `cxp_inbound_fuzz_test` / `cxp_stale_manifest_test`.
- [ ] **CXP robustness manual smoke.** Launch NetCrux while another process holds the CXP port → comes up fully functional with a "cross-probe unavailable" status, no crash; macOS network.server entitlement bind smoke (§9.8) — `[Coverage: MANUAL]`.

## About Box (shared `crux_about_dialog`) (§10)

- [ ] **Help → About NetCrux** opens the shared dialog (desktop) / route (mobile); title "About NetCrux" + tagline render — `[Coverage: WIDGET]` (`test/features/about/netcrux_about_dialog_test.dart`) + `[Coverage: MANUAL]` (real window).
- [ ] **Version / Platform sections** show Version, Build, Commit, OS, Architecture, Flutter, Dart from `aboutBuildInfoProvider` — `[Coverage: WIDGET]` (version + SHA from stub) + `[Coverage: MANUAL]` (real package_info / OS).
- [ ] **Branding banner** shows the Ferrite Engineering logo + "© 2025 Ferrite Engineering" — `[Coverage: WIDGET]` (company name) + `[Coverage: MANUAL]` (logo asset).
- [ ] **"Public Beta" chip** present under `kBetaPeriod = true`, absent under `false` — `[Coverage: WIDGET]` (`betaPeriodProvider` override true/false).
- [ ] **Edition chip hidden for open-core; "EDU" badge for `LicenseTier.edu`** (dialog is not tier-gated — opens for every tier) — `[Coverage: WIDGET]` (edition-chip group).
- [ ] **Two action buttons** — Visit Website + Copy Version Info present; Copy enabled once build info loads — `[Coverage: WIDGET]` (action-button group).
- [ ] **Visit Website** opens `https://ferriteengineering.com`; **Copy Version Info** copies the structured paragraph + shows "Version info copied" snackbar — `[Coverage: MANUAL]`.
- [ ] No exception / overflow in en / zh_CN / ja / ko locale sweeps — `[Coverage: WIDGET]` (locale-sweep group).

## Beta Release Infrastructure (§11)

### Update mechanism (§11.1)

- [ ] Launch with auto-check on and a current build — **nothing** is shown (no flash, no toast) — `[Coverage: UNIT]` (`test/features/update/update_status_state_machine_test.dart`) + `[Coverage: MANUAL]` (live).
- [ ] Manifest advertising a newer version → banner reads `NetCrux <version> is available.` above a fully usable workspace — `[Coverage: WIDGET]` (`test/features/update/widgets/update_banner_mount_test.dart`) + `[Coverage: MANUAL]`.
- [ ] **Update Now** opens `https://netcrux.app/download`; **View Changes** opens the manifest changelog and is absent when the manifest has none — `[Coverage: WIDGET]` (same file) + `[Coverage: MANUAL]` (real browser).
- [ ] **Dismiss** hides the strip for the session; a newer version later re-surfaces it — `[Coverage: WIDGET]` (same file).
- [ ] **Mandatory update renders no close affordance at all** — `[Coverage: WIDGET]` (same file).
- [ ] Manual check (Help menu / palette / About box) reports up-to-date, failure, or surfaces the banner — `[Coverage: UNIT]` (`test/features/update/update_status_state_machine_test.dart`) + `[Coverage: WIDGET]` (`test/features/about/netcrux_about_dialog_beta_actions_test.dart`) + `[Coverage: MANUAL]` (snackbar copy).
- [ ] Settings → General → "Automatically check for updates": on by default, persists across relaunch, and **off suppresses every automatic check while the manual one still runs** — `[Coverage: WIDGET]` (`test/features/settings/screens/settings_auto_update_tile_test.dart`) + `[Coverage: UNIT]` (`test/services/settings/netcrux_settings_codec_test.dart`, `test/features/update/netcrux_update_overrides_test.dart`).
- [ ] Malformed / truncated / type-mismatched manifest never crashes and never shows a banner — `[Coverage: PACKAGE]` (`crux_updates` fail-soft parser) + `[Coverage: MANUAL]`.
- [ ] Web viewer never shows the banner (the check still runs for `server_time`) — `[Coverage: WIDGET]` (`isWeb` seam) + `[Coverage: MANUAL]` (real browser).
- [ ] Update copy renders in en / zh_CN / zh / ja / ko with the version interpolated — `[Coverage: WIDGET]` (`test/core/updates/netcrux_update_strings_test.dart`).
- [ ] Check for Updates is **not** tier-gated under either `kBetaPeriod` value; no `PRO`/`ENT` badge or `" (PRO)"` suffix — `[Coverage: UNIT]` (`test/core/shortcuts/netcrux_action_test.dart`) + `[Coverage: MANUAL]`.

### Beta issue reporter (§11.2)

- [ ] **Help → Submit Issue** (also palette and About box) opens the reporter — `[Coverage: WIDGET]` (`test/features/about/netcrux_about_dialog_beta_actions_test.dart`) + `[Coverage: MANUAL]`.
- [ ] Four category tiles; **App & Environment is locked on**, the other three toggle; the preview updates live — `[Coverage: PACKAGE]` (`crux_issue_reporter`) + `[Coverage: MANUAL]`.
- [ ] **PRIVACY — read the Session State preview: no `/`, no `\`, no source filename, no module / instance / net name, no Yosys binary path** — `[Coverage: UNIT]` (`test/features/issue_reporter/providers/netcrux_issue_session_context_test.dart`) + `[Coverage: MANUAL]` (eyes on the real preview).
- [ ] Session State reports **non-zero** counts for a loaded design, and the counts follow the **active** tab under split panes / multiple tabs — `[Coverage: UNIT]` (same file) + `[Coverage: MANUAL]` (tab switch).
- [ ] Yosys stderr is **not** in the report (it quotes source paths) — `[Coverage: UNIT]` (`test/features/issue_reporter/netcrux_issue_reporter_overrides_test.dart`).
- [ ] Submit copies the body, opens the pre-filled GitHub form, and (desktop) writes + reveals the screenshot PNG — `[Coverage: MANUAL]`.
- [ ] Over-long report drops the body from the URL and the toast changes to the paste wording — `[Coverage: PACKAGE]` + `[Coverage: MANUAL]`.
- [ ] Reporter chrome renders in en / zh_CN / zh / ja / ko; the **issue body stays English** — `[Coverage: WIDGET]` (`test/core/issue_reporter/netcrux_issue_reporter_strings_test.dart`) + `[Coverage: MANUAL]`.
- [ ] Repository slug is `Ferrite-Engineering/netcrux` regardless of `kBetaPeriod`; open to every tier, no badge, no upgrade dialog — `[Coverage: UNIT]` (`test/features/issue_reporter/netcrux_issue_reporter_overrides_test.dart`) + `[Coverage: MANUAL]` (real URL).

### Beta expiry (§11.3)

- [ ] No `--dart-define=BETA_EXPIRY` (every developer and post-beta build) → **never** warns or blocks — `[Coverage: UNIT]` (`test/features/beta_expiry/widgets/beta_expiry_gate_test.dart`) + `[Coverage: MANUAL]`.
- [ ] Inside the warning window → dismissible strip with the correct day count and a working **Download**; dismissal lasts the session and **returns on resume** — `[Coverage: WIDGET]` (same file) + `[Coverage: MANUAL]` (resume).
- [ ] On/after the expiry date → **blocking modal with no dismiss affordance**, back gesture blocked, Download + Quit both wired — `[Coverage: WIDGET]` (same file) + `[Coverage: MANUAL]` (Windows/Linux custom chrome, where Quit is the only exit).
- [ ] The blocking modal covers the update banner when both would show — `[Coverage: MANUAL]`.
- [ ] **Clock rollback cannot revive an expired build or escape the warning window**; a clock set *forward* still expires; a never-online install falls back to the device clock — `[Coverage: UNIT]` (same file, clock-tampering group) + `[Coverage: MANUAL]` (real system clock).
- [ ] Server-time watermark is monotonic, persisted, reloaded on launch, and a corrupt value is ignored — `[Coverage: UNIT]` (`test/features/update/providers/observed_server_time_provider_test.dart`).
- [ ] Invalid `BETA_EXPIRY` (month 13, Feb 30, negative) is treated as "never expires" — `[Coverage: PACKAGE]` (`crux_license`).
- [ ] Banner + modal render in en / zh_CN / ja / ko, including the singular (`=1`) day form; every control clears 44 dp — `[Coverage: WIDGET]` (`test/features/beta_expiry/widgets/beta_expiry_gate_test.dart`).
- [ ] Not tier-gated: a Pro licence does not extend a beta build's shelf life, and a `kBetaPeriod = false` build never expires — `[Coverage: PACKAGE]` + `[Coverage: MANUAL]`.

### Tier badging during the beta (§11.4)

- [ ] Every Pro/Enterprise action shows a `PRO`/`ENT` chip in the command palette and a `" (PRO)"` / `" (ENT)"` suffix in the native menu bar — `[Coverage: UNIT/WIDGET]` (`test/core/shortcuts/netcrux_action_test.dart`, `test/core/shortcuts/action_tier_label_test.dart`, `test/features/command_palette/widgets/command_palette_dialog_test.dart`, `test/features/menu_bar/widgets/desktop_menu_bar_test.dart`) + `[Coverage: MANUAL]` (visual).
- [ ] Open Core actions (Check for Updates, Submit Issue, About, every clear/dismiss) carry **no** badge or suffix — `[Coverage: UNIT]` (`test/core/shortcuts/netcrux_action_test.dart`).
- [ ] Every discovery surface agrees with the descriptor table — `[Coverage: UNIT]` (`test/core/shortcuts/action_surface_conformance_test.dart`).
- [ ] **`kBetaPeriod = true`: every badged Pro action still activates at Open Core tier** (badge communicates, gate is open) — `[Coverage: WIDGET]` (`test/features/workspace/screens/workspace_screen_gating_test.dart`).
- [ ] **`kBetaPeriod = false`: an insufficient tier raises `NetcruxUpgradeDialog` rather than silently no-oping; a satisfied tier reaches the opener** — `[Coverage: WIDGET]` (same file).
- [ ] About box shows the **Public Beta** chip while `kBetaPeriod` is `true` and hides it when `false` — `[Coverage: WIDGET]` (`test/features/about/netcrux_about_dialog_test.dart`).

## Telemetry — cross-platform end-to-end pass (staging)

> **Run 2026-08-05/06** against the **staging** dataset `crux_telemetry_dev`, from
> builds made with `--dart-define=TELEMETRY_DEV=true`. The pipeline, the switches and
> the dataset layout are maintained with the telemetry backend, outside this repository.
>
> **Method per cell.** Build with the dev flag, launch, let the app settle, quit,
> **launch again** — the launch flush ships the *previous* session's queue — quit,
> then read the dataset after the 60–90 s ingest delay. No UI interaction is needed,
> because under the dev flag consent `unset` counts as `enabled`.
>
> **Attribution.** All four products ship `0.6.0`, so `app_version` cannot separate
> the runs. Rows are attributed by **`installation_id` (`blob8`)**: every platform has
> its own app-support container or browser origin, so each run mints a distinct id
> (recorded below). Runs were serialised, so the UTC window corroborates the id.
> Bring-up probe rows are excluded by `blob2 = '0.6.0'` (probes are `8.8.x` / `9.8.x`
> / `9.9.x`), and the Worker's own contract fixture by
> `blob8 != '6f1b0d3e-2a44-4c9e-9f1a-8d5b7c2e4a10'`.

| Platform | `os` | `form_factor` expected | observed | Result |
|---|---|---|---|---|
| macOS 26.6 (Apple silicon), release | `macos` | `desktop` | `desktop` | **PASS** |
| Chrome 151, release web build | `web` | `web` | `web` | **PASS** — re-run 2026-08-06 after the D1 fix; installation `4818fdcc-b53d-43f4-9e3c-81a6c6ea3494` |
| Windows | `windows` | `desktop` | — | **DEFERRED** — no Windows machine on this host |
| Linux | `linux` | `desktop` | — | **DEFERRED** — no Linux machine on this host |
| iOS / Android | — | — | — | **N/A — NetCrux ships no mobile target.** The repo has `macos/`, `web/`, `windows/` and `linux/` runners and no `ios/` or `android/` directory, so there is no build to run and nothing is being deferred for want of hardware |

NetCrux's `form_factor` derives from `isDesktopPlatform` alone — it has no width breakpoint, and with no mobile runners its `phone` branch is unreachable by construction. `desktop` on macOS is therefore the only answer it can give, and it gave it. Expected, not a gap.

- [x] The passing row carried the right envelope: `product=netcrux`, `locale=en`, `country=US` (stamped at the edge), `license_tier=openCore`, and a normalized `session_start` — `[Coverage: MANUAL]` (staging dataset)
- [x] `_sample_interval = 1` on every row, so the `product/event_name/properties` index is not sampling at this volume — `[Coverage: MANUAL]`
- [x] A second catalog event reached the dataset from the same session, confirming the path is not launch-event-only: `design.elaborated {cached=false, language=verilog, source=rtl}` — `[Coverage: MANUAL]`

**Installation ids** — macOS `91ec1efc-1a65-46e3-992d-3945d9474de5` (2026-08-05) ·
Chrome web `4818fdcc-b53d-43f4-9e3c-81a6c6ea3494` (re-run 2026-08-06).

### Re-run 2026-08-06 — D1, D2 and D3 fixed

All three defects are fixed in `crux_telemetry` and pinned here (crux-shared
`1c30b1f`). The cells that failed were re-run on real clients; nothing was
substituted with a `curl`.

- [x] **Web now transmits.** A single 100 s Chrome session against the release
  web build sent `workspace.restored` with `os=web`, `form_factor=web`,
  `locale=en`, `license_tier=openCore`, `country=US` — installation
  `4818fdcc-…`, ingested ~70 s after the page load. Previously: zero rows over
  two page loads. `[Coverage: MANUAL]`
- [x] **NetCrux's `form_factor` still answers rather than deferring.** D2 made
  the seam `Provider<String?>` so a product whose idiom comes from the widget
  tree can say "not yet"; NetCrux derives from `isDesktopPlatform` and `kIsWeb`,
  both knowable before the first frame, so it must keep returning a value.
  Asserted twice — `[Coverage: UNIT]`
  (`test/services/telemetry/telemetry_platform_test.dart`: over every host, and
  through the wired seam in a bare container with no widget tree mounted, which
  is the launch-flush situation).
- [x] **Consent `disabled` with the dev flag sends nothing.** Exercised on
  WaveCrux against the shared gate — `[Coverage: MANUAL]` — and held here by the
  gating matrix, which now settles the store before asserting rather than
  seeding `notifier.state` synchronously. `[Coverage: UNIT]`

### Picking up the deferred cells on another machine

```bash
# On a Windows or Linux host:
flutter build windows --release --dart-define=TELEMETRY_DEV=true   # or: build linux
#   launch the built binary twice, quitting in between, then query the staging
#   dataset for the last day's netcrux rows (maintainer access).
```

### The negative cases

- [x] **A beta build without the dev flag performs zero telemetry HTTP.** Primary
  evidence is the traffic-level beta-inert test — `[Coverage: PACKAGE]`
  (`crux_telemetry`'s `telemetryServiceProvider` suite, 64 tests, sweeps all 12
  `policy × consent` cells asserting an empty request list) — plus this repo's own
  group — `[Coverage: UNIT]` (`test/core/providers/telemetry_service_provider_test.dart`).
  Corroborated at runtime — `[Coverage: MANUAL]`: a NetCrux release built with **no**
  `--dart-define` was launched twice and **never created `telemetry_queue.jsonl` at
  all** (the live service is never constructed, so `record()` hits the no-op and
  nothing touches disk or the network), and the **production** dataset
  `crux_telemetry` holds **0 rows over 90 days**.
- [x] **Consent `disabled` with the dev flag sends nothing.** — **PASS** on the
  2026-08-06 re-run. Exercised on WaveCrux (shared gate; every product resolves
  the same `telemetryEnabledProvider` from `crux_telemetry`, so the fix is
  suite-wide). See D3 below.

### Defects found — all three FIXED on 2026-08-06

- [x] **D1 — web builds never transmit; the `web` `form_factor` is unreachable in
  practice.** All four products' release web builds produced **zero** rows across two
  page loads each, netcrux included. A full Chrome `--log-net-log` capture over a 90 s
  web session shows **zero requests to `telemetry.edacrux.app`** (the same capture
  holds 300 references to the page's own assets, so the capture itself is sound).
  Mechanism, reproduced hermetically against `LiveTelemetryService` with a
  `directoryFactory` that throws (exactly what web does): on web `path_provider` is
  unavailable, so `TelemetryEventQueue` degrades to memory-only and `load()` returns
  empty; `start()`'s launch flush therefore runs against an empty `_pending` and
  returns at `if (_pending.isEmpty) return;` **without arming anything**; the only
  remaining trigger is the 6-hourly timer, which no browser session survives. On
  desktop the disk queue carries events to the next launch, which is why only web is
  affected. **Not a shipping-harm defect today** (the pipeline is dark-launched until
  `kBetaPeriod` flips), but the field exists to answer "does the web build earn its
  maintenance" and it cannot. Fix is a design call between (a) backing the queue with
  the `TelemetryStorage` seam on web so it survives a reload, or (b) arming a short
  follow-up flush when the launch flush finds the queue empty — (b) changes the
  documented "this session's events go out on the next six-hourly tick or the next
  launch" contract on every platform. **FIXED 2026-08-06** in
  `crux_telemetry` 0.3.0 (crux-shared `1c30b1f`) — option (b), scoped to the
  volatile queue only, so desktop and mobile keep the contract verbatim: where
  `hasPersistentBacking()` is false, `record()` arms one flush per
  `volatileFlushInterval` (60 s) and the host's hidden/paused/detached signal
  flushes too. Verified above.
- [x] **D2 — `form_factor` races the first layout (WaveCrux only).** WaveCrux's
  derivation reads a size that is pushed from inside `MaterialApp.builder`, while the
  envelope is resolved at launch-flush time, ahead of it; on a Pixel Tablet the same
  build in the same orientation reported `desktop` three times and `tablet` once.
  **NetCrux is not affected**: its `telemetryFormFactorFor` takes `isWeb` and
  nothing else, so it has no size to race. **FIXED 2026-08-06** in WaveCrux;
  the shared half is `telemetryFormFactorProvider` becoming
  `Provider<String?>`, where `null` means "not knowable yet" and the flush
  defers. NetCrux keeps returning a value, and now says so in code and in two
  tests — see the re-run notes above, and WaveCrux's checklist §13A.3.
- [x] **D3 — a stored consent of `disabled` still transmits under the dev flag.**
  Exercised on WaveCrux: with `flutter.telemetry.consent = disabled` and a
  `TELEMETRY_DEV=true` build, two launches produced a real row in the staging dataset
  from the very installation whose consent is `disabled`. Cause:
  `TelemetryConsentStore.build()` publishes `TelemetryConsentState.unset`
  **synchronously** and loads the persisted value asynchronously, while
  `telemetryEnabledProvider` computes `consent == enabled || (dev && consent ==
  unset)` — so for the first frames of a cold start a stored `disabled` is
  indistinguishable from "not answered", and under the dev flag the gate opens.
  **Blast radius is dev builds only**: with `dev == false` the beta branch
  short-circuits synchronously during the beta, and post-flip the gate reads
  `consent == enabled`, where `unset` fails safe. No shipping build is affected and
  the beta promise is intact — but the documented guarantee for the dev flag is
  broken. The 36-cell gating matrix cannot catch this: it seeds consent by assigning
  `notifier.state` directly, so **no cell exercises a value read back through
  storage**. Fix: gate the dev-flag `unset` promotion on the store having settled (it
  already owns a `loaded` completer), and add a storage-backed cell to the matrix.
  **NetCrux shares the gate, so it is affected identically.** **FIXED
  2026-08-06** in `crux_telemetry` 0.3.0: the dev-flag promotion of `unset` now
  waits on `telemetryConsentReadyProvider`, the same `loaded` signal the
  disclosure already waited on. The matrix here settles the store before
  asserting, and the package gained a pre-load group that seeds *storage* behind
  a gated read — the gap that let this through. Pinned at crux-shared
  `1c30b1f`.

  One consequence worth recording, because it was found only by re-running on a
  real client: waiting for the store creates a window, and the window is not
  incidental — the store's read does not *start* until something reads the
  telemetry graph, so the first event of every launch (`workspace.restored`,
  from a notifier's `build`) falls inside it by construction. Resolving the
  no-op there **discarded** that event, which on web is the whole session. The
  gate is therefore a tri-state now (`TelemetryGate { open, closed, pending }`)
  and `PendingTelemetryService` buffers the window, replaying into the live
  service when the gate opens and dropping the buffer when it closes. The beta
  never enters that state.

---

## Adding a group

Add a checklist group the same day the corresponding feature ships.

---

## Sign-off

- [ ] All groups above signed off
- [ ] Pro overlay checklist ran cleanly (if signing off a Pro build)
- [ ] Cross-platform smoke pass (Linux + macOS + Windows) for any UI-affecting change
