# NetCrux (Open Core) — Integration Test Status & Backlog

This file tracks the Flutter `integration_test/` suite that exercises a fully
running open-core NetCrux build (started via `bootstrap` from
`package:netcrux/app.dart`). Each entry corresponds to a `[Coverage:
INTEGRATION_TEST]` (or formerly `— pending`) marker in
`verification/VERIFICATION_GUIDE.md`.

The harness lives in `integration_test/helpers/app_driver.dart` and mirrors the
WaveCrux open-core helper (`wavecrux/integration_test/helpers/app_driver.dart`):
`bootNetcrux` launches the real app and the `pumpUntil` / `rootContainer` /
`activeTabContainer` primitives follow the suite-wide conventions (never
`pumpAndSettle(Duration)` — the binding treats the duration as a per-pump
interval, not a timeout).

## Running

NetCrux is desktop-only. Run a single file:

```bash
flutter test integration_test/workspace/restore_round_trip_test.dart -d macos
```

**macOS app-relaunch race.** Running the whole directory in one `flutter test
integration_test` invocation relaunches the app per file and macOS frequently
fails the rapid relaunch ("Unable to start the app on the device"). Run each
file in its own invocation; retry on the relaunch error (it is environmental,
not a test failure). A retry-on-race loop is the reliable driver until the
device-mode runs are wired into CI.

## Implemented (green on macOS)

- [x] §4.2 Seeded-design journey: load → navigate hierarchy → select →
      inspect — `design/seeded_design_journey_test.dart`. First user of the
      **design-seed helper** (see below).
- [x] §4.1.1 Workspace auto-save + restore round-trip —
      `workspace/restore_round_trip_test.dart`
- [x] §4.1.2 Named workspace save / reset / open —
      `workspace/named_workspace_test.dart`
- [x] §4.1.4 Split-pane + move-tab-between-panes mutation contract —
      `workspace/split_pane_test.dart`
- [x] §4.1.5 CLI multi-file open → one tab per file —
      `tabs/cli_multi_file_test.dart`
- [x] §4.1.6 Cold-boot empty-canvas state — `workspace/empty_canvas_boot_test.dart`
      (also the harness smoke test)
- [x] §6.1 CXP server lifecycle (boot-start + settings toggle) —
      `remote_control/cxp_server_lifecycle_test.dart`
- [x] §8.1 Theme preset switch flips MaterialApp brightness —
      `theme/theme_switch_test.dart`
- [x] §7.1 Cone-of-influence seam dispatch (no-op overlay in open-core) —
      `schematic/cone_of_influence_seam_test.dart`
- [x] §7.4 X-trace seam dispatch (empty result in open-core) —
      `schematic/x_trace_seam_test.dart`
- [x] §7.5 Bookmarks/annotations session round trip (in-session store) —
      `session/bookmark_annotation_session_round_trip_test.dart`
- [x] §7.7 Custom cell symbols seam dispatch (built-in painters in
      open-core) — `custom_cell_symbols/custom_cell_symbol_seam_test.dart`
- [x] §6.2 notify_selection emission on canvas selection —
      `remote_control/notify_selection_emission_test.dart`
- [x] §6.3 request_highlight receive → inspector selection / hierarchy nav —
      `remote_control/request_highlight_navigation_test.dart`
- [x] §6.5 Cross-probe panel discovery + event log (two-peer manifest
      exchange) — `remote_control/cross_probe_panel_discovery_test.dart`
- [x] §4.1.3 Tab export as `.netcrux` session → re-open round-trip —
      `session/session_export_round_trip_test.dart`
- [x] §4.1.7 Missing-file / missing-engine recovery surfaces (canvas +
      hierarchy + diagnostics error views) —
      `tabs/missing_engine_recovery_test.dart`
- [x] §4.1.11 Command palette reachable via Help menu after its shortcut is
      unbound; palette does not list itself —
      `command_palette/menu_reachability_test.dart`

## The design-seed helper

`seedDesignIntoNewTab` in `helpers/app_driver.dart` seeds a loaded schematic
without Yosys: it parses a committed netlist-JSON fixture through the real
`YosysJsonParser` and injects the model into the active tab's per-tab
`loadedNetlistProvider` (`LoadedNetlist.setModel`). Boot with
`extraOverrides: designSeedBootOverrides()` — the helper throws otherwise.
The default fixture is `fixtures/design_seed_netlist.dart` (a generated
Dart-const mirror of `test/fixtures/netlist/design_seed/generated/`;
regenerate with `dart run tool/generate_design_seed_fixture.dart`).

Two hard-won traps, so they aren't rediscovered:

- **Never let the seeded tab's elaboration keep retrying.** Riverpod 3
  auto-retries failed providers; before `loadedNetlistProvider` /
  `currentLaidOutGraphProvider` opted out (`noElaborationRetry`), each
  backoff retry clobbered the injected model, re-rooted the hierarchy
  selection, and the rebuild churn even swallowed `tester.tap` gestures.
- **Don't back the tab's project with a real placeholder file.** macOS
  FSEvents can replay the file's own creation after the seed lands, and the
  per-tab source watcher invalidates `loadedNetlistProvider` on it. The
  helper uses a nonexistent pseudo path (watching a missing path emits
  nothing; the pinned-unavailable Yosys probe errors before any file IO).

**When the pipeline will run again, use the reloadable seed.**
`seedDesignIntoNewTab` injects its model after an elaboration that always
fails, so anything that re-runs the pipeline lands on that failure instead of
the design. Reopening a session does exactly that: it names the session's
sources and loads them afresh. `seedNetlistDocumentIntoNewTab` (boot with
`netlistDocumentSeedBootOverrides(json)`) opens a nonexistent `.json` path
instead, which the pipeline reads as a pre-built netlist through an overridden
`prebuiltNetlistLoaderProvider` — so the design comes back every time the
pipeline runs, through the real loader and parser.

## The EULA

`bootNetcrux` records acceptance of the current EULA before it boots
(`acceptEulaForTest`), and restores whatever was recorded when the test ends.
Without it `CruxEulaGate` puts a modal barrier over the whole app: finders
still match the tree underneath, so the symptom is a `tap` that lands on the
barrier, not a visible dialog. Only a test of the agreement itself passes
`acceptEula: false`.

## Pending — UI-navigation surface

None currently — the last three items (§4.1.3, §4.1.7, §4.1.11) landed; see
"Implemented" above.
