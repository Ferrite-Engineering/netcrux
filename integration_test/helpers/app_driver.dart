// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/helpers/app_driver.dart
//
// Open-core NetCrux integration-test helper library.
//
// Each function here targets a complete running app (started via
// [bootstrap] from `package:netcrux/app.dart`) and is intended for use
// inside a `testWidgets` body that runs under the `integration_test`
// package's [IntegrationTestWidgetsFlutterBinding].
//
// Usage pattern (one `testWidgets` per integration-test file):
//
// ```dart
// void main() {
//   IntegrationTestWidgetsFlutterBinding.ensureInitialized();
//   suppressPlatformSemanticsLeak();
//   testWidgets('boots to the empty-canvas state', (tester) async {
//     await bootNetcrux(tester);
//     expect(find.byType(EmptyCanvasContent), findsOneWidget);
//   });
// }
// ```
//
// The harness mirrors the WaveCrux open-core helper
// (`wavecrux/integration_test/helpers/app_driver.dart`); the timing,
// root-container, and semantics-leak primitives are ported verbatim so the
// suite-wide integration-test conventions stay identical across products.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:crux_yosys/crux_yosys.dart' show YosysAvailability;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/app.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/workspace/widgets/project_tab_content.dart';
import 'package:netcrux/services/web/web_json_loader.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/helpers/app_boot_overrides.dart' show kEulaAcceptedPrefs;

/// Suppresses the macOS embedder's mid-test "semantics enabled" signal so
/// integration tests don't trip the framework's
/// `_verifySemanticsHandlesWereDisposed` check at teardown.
///
/// The macOS embedder asynchronously sends "semantics enabled = true"
/// sometime during the first test that gains focus; the binding lazily
/// acquires a semantics handle that is never released (the platform never
/// sends "enabled = false"), so the late acquisition counts as a leak and
/// the test fails at teardown. Replacing the callback with a no-op after the
/// binding is initialised stops the binding reacting to the platform signal.
///
/// Call once in each integration test's `main()` immediately after
/// [IntegrationTestWidgetsFlutterBinding.ensureInitialized].
void suppressPlatformSemanticsLeak() {
  ui.PlatformDispatcher.instance.onSemanticsEnabledChanged = () {};
}

/// `true` when the integration test runs on a desktop host (macOS / Linux /
/// Windows) rather than a mobile target. NetCrux is desktop-only, but the
/// guard mirrors the cross-suite convention for tests that simulate a
/// device class via `setSurfaceSize`.
bool get skipOnMobileDevice => Platform.isAndroid || Platform.isIOS;

/// Pumps the live tree in [interval] steps until [condition] returns true or
/// [timeout] elapses, then returns whether [condition] held.
///
/// IMPORTANT — use this, NOT `pumpAndSettle(const Duration(seconds: N))`, to
/// wait for work in an integration test. Under
/// [IntegrationTestWidgetsFlutterBinding] (a [LiveTestWidgetsFlutterBinding])
/// the `duration` argument to `pump` / `pumpAndSettle` is the *per-pump
/// real-time interval*, NOT a timeout — `pumpAndSettle(Duration(seconds: 10))`
/// blocks the full ten seconds even when the UI settled instantly. A bounded
/// condition-poll returns the instant the real ready-state is observable and
/// caps the wait at [timeout].
Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 50),
}) async {
  final maxIterations = (timeout.inMilliseconds / interval.inMilliseconds)
      .ceil();
  for (var i = 0; i < maxIterations; i++) {
    if (condition()) return true;
    await tester.pump(interval);
  }
  return condition();
}

/// Returns the root [ProviderContainer] the live app is rendering against.
///
/// Pulled directly off the outermost [UncontrolledProviderScope] widget's
/// public `container` field. The root scope is the one `bootstrap` hands to
/// `runApp` at the very top of the tree; per-tab [ActiveTabScope] scopes are
/// nested inside it, so `.first` is always the root.
ProviderContainer rootContainer(WidgetTester tester) {
  final scope = tester.widget<UncontrolledProviderScope>(
    find.byType(UncontrolledProviderScope).first,
  );
  return scope.container;
}

/// Returns the singleton [TabContainerManager] constructed at bootstrap,
/// resolved off the live [WorkspaceManagersScope].
TabContainerManager tabContainerManager(WidgetTester tester) {
  final scope = tester.widget<WorkspaceManagersScope>(
    find.byType(WorkspaceManagersScope).first,
  );
  return scope.tabContainerManager;
}

/// Returns the workspace's currently-active tab id, or `null` when the
/// workspace is empty (empty-canvas state) or still hydrating.
TabId? activeTabId(WidgetTester tester) =>
    rootContainer(tester).read(netcruxWorkspaceProvider).value?.activeTabId;

/// Returns the per-tab [ProviderContainer] for the workspace's currently
/// active tab.
///
/// Per-tab state (`currentProjectProvider`, `loadedNetlistProvider`,
/// `selectedElementProvider`, the trace / x-trace / diff / FSM / CDC
/// providers, …) is scoped per-tab in `netcruxTabOverrides`, so reads of
/// those providers must go through this container rather than the root one.
ProviderContainer activeTabContainer(WidgetTester tester) {
  final id = activeTabId(tester);
  if (id == null) {
    throw StateError(
      'activeTabContainer: no active tab — the workspace is empty. '
      'Open a tab before resolving the active-tab container.',
    );
  }
  return tabContainerManager(tester).containerFor(id);
}

/// The live workspace value, or `null` while it is still hydrating.
Workspace<NetcruxTabPayload>? liveWorkspaceOrNull(WidgetTester tester) =>
    rootContainer(tester).read(netcruxWorkspaceProvider).value;

/// The live workspace value. Throws if the workspace has not hydrated yet —
/// [bootNetcrux] awaits hydration, so this is safe after a boot.
Workspace<NetcruxTabPayload> liveWorkspace(WidgetTester tester) {
  final ws = liveWorkspaceOrNull(tester);
  if (ws == null) {
    throw StateError('liveWorkspace: workspace has not hydrated yet');
  }
  return ws;
}

/// The number of tabs currently open across every pane.
int tabCount(WidgetTester tester) =>
    liveWorkspaceOrNull(tester)?.tabs.length ?? 0;

/// Loads the persisted `{appSupportDir}/workspace.json` through a FRESH
/// [WorkspaceService] instance — what the next cold start would hydrate.
///
/// Used by the workspace round-trip tests: after driving the live workspace
/// and calling `flushPendingSave()`, this reads the on-disk document back
/// without going through the live notifier, proving the persisted shape.
Future<Workspace<NetcruxTabPayload>> freshWorkspaceLoad() {
  return WorkspaceService<NetcruxTabPayload>(
    codec: const NetcruxWorkspaceCodec(),
  ).load();
}

/// Saves [workspace] to [path] and reads it back through fresh services —
/// the named-workspace (`File → Save/Open Workspace…`) on-disk round-trip.
Future<Workspace<NetcruxTabPayload>> namedWorkspaceRoundTrip(
  String path,
  Workspace<NetcruxTabPayload> workspace,
) async {
  final service = WorkspaceService<NetcruxTabPayload>(
    codec: const NetcruxWorkspaceCodec(),
  );
  await service.saveToPath(path, workspace);
  return service.loadFromPath(path);
}

/// Deletes the auto-managed `{appSupportDir}/workspace.json` so a fresh
/// launch starts from an empty workspace.
///
/// Integration tests run sequentially against a shared application-support
/// directory; a test that persists a workspace leaves a `workspace.json`
/// behind, which the next launch would hydrate. Call this before [bootNetcrux]
/// (or pass `clearWorkspace: true`, the default) so every boot is hermetic.
Future<void> clearPersistedWorkspace() async {
  await WorkspaceService<NetcruxTabPayload>(
    codec: const NetcruxWorkspaceCodec(),
  ).clear();
}

/// Records that this installation has accepted the current EULA, and puts
/// back whatever was recorded before once the test ends.
///
/// The app mounts `CruxEulaGate` at its root, and an installation with no
/// recorded acceptance gets its blocking modal over everything. The failure
/// that causes in a test is not a visible dialog: finders still match the
/// tree underneath, so the first `tap` lands on the modal barrier instead and
/// the test fails somewhere downstream of it.
///
/// Written through `SharedPreferences.getInstance()` — the store the
/// production `NetcruxEulaStorage` reads — rather than by overriding the
/// storage provider, which the production override list already binds. The
/// value is the unit-test seam's [kEulaAcceptedPrefs], so both kinds of test
/// accept the same agreement. Seeding is honest because the gate is not what
/// these tests are about; `test/static/eula_gate_reachability_test.dart` is
/// what keeps the gate mounted.
Future<void> acceptEulaForTest() async {
  final prefs = await SharedPreferences.getInstance();
  final previous = <String, Object?>{
    for (final key in kEulaAcceptedPrefs.keys) key: prefs.get(key),
  };
  for (final MapEntry(:key, :value) in kEulaAcceptedPrefs.entries) {
    await prefs.setString(key, value as String);
  }
  addTearDown(() async {
    for (final MapEntry(:key, :value) in previous.entries) {
      if (value is String) {
        await prefs.setString(key, value);
      } else {
        await prefs.remove(key);
      }
    }
  });
}

/// Records that this installation has answered the first-launch
/// usage-statistics disclosure, declining, and restores whatever was
/// recorded before once the test ends.
///
/// The public beta is over, so the telemetry gate is live: an installation
/// that has never answered gets `TelemetryConsentDisclosure` over the whole
/// app, and the answer arrives asynchronously — the store reads
/// `SharedPreferences` — so the dialog lands part-way through a journey
/// rather than at boot. The failure it causes is not a visible dialog
/// either: finders keep matching the tree underneath, and a `tap` lands on
/// the barrier instead. That is what took three files down on the first
/// post-beta sweep, each reporting a hit on a `_RenderColoredBox`.
///
/// Declined rather than accepted, so a test can never post telemetry:
/// nothing is collected and the pipeline stays inert.
Future<void> answerTelemetryDisclosureForTest() async {
  final prefs = await SharedPreferences.getInstance();
  final previous = prefs.getString(kTelemetryConsentKey);
  await prefs.setString(
    kTelemetryConsentKey,
    TelemetryConsentState.disabled.name,
  );
  addTearDown(() async {
    if (previous == null) {
      await prefs.remove(kTelemetryConsentKey);
    } else {
      await prefs.setString(kTelemetryConsentKey, previous);
    }
  });
}

/// Boots the open-core NetCrux app via [bootstrap] and pumps until the first
/// frame settles.
///
/// [args] are forwarded to `bootstrap` (CLI launch intent — file paths, or
/// `--workspace` / `--session` flags). [extraOverrides] layer onto the root
/// container exactly as the Pro overlay's `proOverrides` do, letting a test
/// seed a fake elaborated netlist without a real Yosys subprocess.
///
/// [acceptEula] records acceptance of the current EULA first (see
/// [acceptEulaForTest]) and answers the usage-statistics disclosure (see
/// [answerTelemetryDisclosureForTest]) — the two dialogs a first launch puts
/// over the app. Only a test of one of them turns it off.
///
/// Call this exactly once per `testWidgets` body — the Flutter framework
/// throws if `runApp` runs more than once in a single test process.
Future<void> bootNetcrux(
  WidgetTester tester, {
  List<String> args = const [],
  List<Override> extraOverrides = const [],
  List<Override> extraTabOverrides = const [],
  bool clearWorkspace = true,
  bool acceptEula = true,
  Size surfaceSize = const Size(1600, 1000),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  if (clearWorkspace) {
    await clearPersistedWorkspace();
    addTearDown(clearPersistedWorkspace);
  }
  if (acceptEula) {
    await acceptEulaForTest();
    await answerTelemetryDisclosureForTest();
  }
  await bootstrap(
    args: args,
    extraOverrides: extraOverrides,
    extraTabOverrides: extraTabOverrides,
  );
  await tester.pump();
  // Let the workspace AsyncNotifier hydrate and the first route build. The
  // empty-canvas branding assets are not resolvable in the headless test
  // bundle, so drain fixed frames instead of pumpAndSettle.
  await pumpUntil(
    tester,
    () => rootContainer(tester).read(netcruxWorkspaceProvider).hasValue,
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Design-seed helper — a loaded schematic without Yosys
// ───────────────────────────────────────────────────────────────────────────

/// Sentinel `unavailableReason` [designSeedBootOverrides] installs, so
/// [seedDesignIntoNewTab] can verify the boot was actually seeded.
const String kDesignSeedYosysUnavailableReason = 'design-seed-harness';

/// Root-scope overrides required by [seedDesignIntoNewTab]. Pass to
/// [bootNetcrux] (`extraOverrides: designSeedBootOverrides()`).
///
/// Pins the Yosys availability probe to "unavailable" so the per-tab
/// elaboration pipeline settles on a fast, deterministic [AsyncError]
/// without ever spawning a subprocess — regardless of whether the test
/// host has Yosys on PATH. Seeded-design journeys must be hermetic: the
/// design comes from a committed netlist-JSON fixture parsed through
/// [YosysJsonParser], never from a live elaboration.
List<Override> designSeedBootOverrides() => <Override>[
  yosysAvailabilityProvider.overrideWith(
    (ref) async => const YosysAvailability.notFound(
      reason: kDesignSeedYosysUnavailableReason,
    ),
  ),
];

/// The per-tab container and parsed model produced by
/// [seedDesignIntoNewTab].
typedef SeededDesign = ({ProviderContainer tab, NetlistModel model});

/// Opens a fresh project tab and injects [netlistJson] (a committed
/// Yosys-shaped fixture, e.g. `designSeedNetlistJson` from
/// `integration_test/fixtures/design_seed_netlist.dart`) as the tab's
/// elaborated design — no Yosys involved. Returns the tab's
/// [ProviderContainer] plus the parsed [NetlistModel].
///
/// Requires a boot with [designSeedBootOverrides] applied; throws
/// [StateError] otherwise. Sequence:
///
///  1. Parse [netlistJson] through the real [YosysJsonParser].
///  2. Open a tab whose payload names a real (placeholder) temp source
///     file — the schematic center only mounts for a non-empty project,
///     and the per-tab source watcher wants an existing path.
///  3. Wait for the tab's [ProjectTabContent] to mount so its
///     `loadedNetlistProvider` listener (which forwards models into the
///     hierarchy tree) is armed.
///  4. Push the project into the per-tab [currentProjectProvider], then
///     wait for the elaboration pipeline to settle on its guaranteed
///     yosys-unavailable [AsyncError] — so no late pipeline result can
///     clobber the injected model.
///  5. Inject via `LoadedNetlist.setModel` (the documented in-process
///     fixture path that bypasses yosys) and wait until the hierarchy
///     tree owns the model.
Future<SeededDesign> seedDesignIntoNewTab(
  WidgetTester tester, {
  required String netlistJson,
  String displayName = 'seeded design',
}) async {
  final model = const YosysJsonParser().parse(netlistJson);

  // Pseudo source path — deliberately nonexistent. The availability guard
  // makes the elaboration pipeline throw before any file IO, and the
  // per-tab source watcher's `File.watch` on a missing path never emits
  // (platform watch errors are silently ignored), so no stray filesystem
  // event can re-run elaboration and clobber the injected model. A REAL
  // placeholder file is the trap here: macOS FSEvents can replay the
  // file's own creation after the seed lands. The path exists only so
  // `project.sourceFiles` is non-empty, which is what mounts the
  // schematic center.
  const pseudoSource = '/netcrux-design-seed/seed.v';

  await rootContainer(tester)
      .read(netcruxWorkspaceProvider.notifier)
      .openTab(
        displayName: displayName,
        payload: const NetcruxTabPayload(sourceFiles: <String>[pseudoSource]),
      );
  await pumpUntil(tester, () => activeTabId(tester) != null);
  final tab = activeTabContainer(tester);

  // Guard: the availability probe must be the seeded fake, otherwise the
  // pipeline may spawn a real Yosys whose late result races the injection.
  final availability = await tab.read(yosysAvailabilityProvider.future);
  if (availability.isAvailable ||
      availability.unavailableReason != kDesignSeedYosysUnavailableReason) {
    throw StateError(
      'seedDesignIntoNewTab: boot without designSeedBootOverrides() — pass '
      'extraOverrides: designSeedBootOverrides() to bootNetcrux first.',
    );
  }

  // The tab content must be mounted BEFORE the model lands: its
  // `ref.listen(loadedNetlistProvider, …)` only reacts to changes.
  final mounted = await pumpUntil(
    tester,
    () => tester.any(find.byType(ProjectTabContent)),
  );
  if (!mounted) {
    throw StateError(
      'seedDesignIntoNewTab: ProjectTabContent never mounted for the new tab',
    );
  }

  tab.read(currentProjectProvider.notifier).setSourceFiles(
    const <String>[pseudoSource],
  );
  final settled = await pumpUntil(
    tester,
    () => tab.read(loadedNetlistProvider).hasError,
  );
  if (!settled) {
    throw StateError(
      'seedDesignIntoNewTab: elaboration pipeline never settled on the '
      'expected yosys-unavailable error',
    );
  }

  tab.read(loadedNetlistProvider.notifier).setModel(model);
  final treeReady = await pumpUntil(
    tester,
    () => identical(tab.read(hierarchyTreeProvider).model, model),
  );
  if (!treeReady) {
    throw StateError(
      'seedDesignIntoNewTab: hierarchy tree never received the seeded model',
    );
  }
  return (tab: tab, model: model);
}

// ───────────────────────────────────────────────────────────────────────────
// Reloadable design seed — a design the pipeline itself can load again
// ───────────────────────────────────────────────────────────────────────────

/// The location [netlistDocumentSeedBootOverrides] serves its netlist at.
///
/// A `.json` name makes the tab's project a pre-built netlist, which the
/// elaboration pipeline reads through `prebuiltNetlistLoaderProvider` rather
/// than handing to Yosys. The path does not exist, so the per-tab source
/// watcher never reports a change to it — the same reason
/// [seedDesignIntoNewTab] uses a nonexistent source.
const String kSeededNetlistDocumentPath = '/netcrux-design-seed/seed.json';

/// Root-scope overrides for [seedNetlistDocumentIntoNewTab]: everything
/// [designSeedBootOverrides] pins, plus a pre-built-netlist loader that
/// answers [kSeededNetlistDocumentPath] with [netlistJson].
///
/// **Use this seed when the pipeline will run again.** [seedDesignIntoNewTab]
/// injects its model after a pipeline that always fails, so anything that
/// re-runs the pipeline — reopening a session, which names the design's
/// sources and loads them afresh — lands on that failure instead of the
/// design. Here the pipeline itself produces the design, through the real
/// loader and parser, every time it runs. Any other location is read as the
/// production loader would read it.
List<Override> netlistDocumentSeedBootOverrides(String netlistJson) =>
    <Override>[
      ...designSeedBootOverrides(),
      prebuiltNetlistLoaderProvider.overrideWithValue(
        PrebuiltNetlistLoader(
          read: (location) async => location == kSeededNetlistDocumentPath
              ? netlistJson
              : fetchWebJson(location),
        ),
      ),
    ];

/// Opens a fresh project tab on [kSeededNetlistDocumentPath] and waits until
/// the pipeline has loaded it and the hierarchy tree holds it. Returns the
/// tab's [ProviderContainer] and the loaded [NetlistModel].
///
/// Requires a boot with [netlistDocumentSeedBootOverrides]; throws
/// [StateError] when the design never loads or never reaches the tree. The
/// source is set only once the tab's [ProjectTabContent] is mounted, because
/// its `loadedNetlistProvider` listener — which hands the model to the tree —
/// reacts only to changes.
Future<SeededDesign> seedNetlistDocumentIntoNewTab(
  WidgetTester tester, {
  String displayName = 'seeded design',
}) async {
  await rootContainer(tester)
      .read(netcruxWorkspaceProvider.notifier)
      .openTab(
        displayName: displayName,
        payload: const NetcruxTabPayload(
          sourceFiles: <String>[kSeededNetlistDocumentPath],
        ),
      );
  await pumpUntil(tester, () => activeTabId(tester) != null);
  final tab = activeTabContainer(tester);

  final mounted = await pumpUntil(
    tester,
    () => tester.any(find.byType(ProjectTabContent)),
  );
  if (!mounted) {
    throw StateError(
      'seedNetlistDocumentIntoNewTab: ProjectTabContent never mounted',
    );
  }

  tab.read(currentProjectProvider.notifier).setSourceFiles(const <String>[
    kSeededNetlistDocumentPath,
  ]);
  final loaded = await pumpUntil(
    tester,
    () => tab.read(loadedNetlistProvider).value != null,
    timeout: const Duration(seconds: 30),
  );
  if (!loaded) {
    throw StateError(
      'seedNetlistDocumentIntoNewTab: the seeded netlist never loaded — '
      'boot with netlistDocumentSeedBootOverrides(); pipeline state: '
      '${tab.read(loadedNetlistProvider)}',
    );
  }
  final model = tab.read(loadedNetlistProvider).value!;
  final treeReady = await pumpUntil(
    tester,
    () => identical(tab.read(hierarchyTreeProvider).model, model),
  );
  if (!treeReady) {
    throw StateError(
      'seedNetlistDocumentIntoNewTab: hierarchy tree never received the '
      'loaded model',
    );
  }
  return (tab: tab, model: model);
}
