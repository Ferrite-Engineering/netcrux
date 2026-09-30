// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/workspace_recovery_provider.dart';

/// NetCrux's [`AsyncNotifierProvider`]-targeted subclass of
/// `crux_workspace`'s generic [`WorkspaceNotifier<P>`].
///
/// The subclass exists so:
///
/// 1. The provider's notifier type is concrete (`NetcruxWorkspaceNotifier`)
///    rather than the generic `WorkspaceNotifier<NetcruxTabPayload>`, which
///    lets `AsyncNotifierProvider.overrideWith` accept a subclass factory in
///    tests without invariance pain.
/// 2. NetCrux-specific telemetry / instrumentation lands here as
///    `override + super.method()` wrappers — the inherited mutation API
///    (`openTab` / `closeTab` / `reorderTab` / `moveTabToPane` / `splitPaneRight`
///    / `closePane` / `focusOtherPane` / `setActiveTab` / `setActivePane` /
///    `updateTabPayload` / `updateTabDisplayName` / `resetWorkspace` /
///    `replaceWith` / `saveAs` / `loadFrom`) is consumed verbatim by call sites
///    today. There are deliberately no NetCrux-named backward-compat
///    wrappers: they cause generic-invariance issues with
///    `PaneHost.provider`'s typed parameter.
///
/// The constructor accepts an optional [`WorkspaceService`] for test
/// injection; the no-arg construction path (used by the production provider)
/// wires the production [`WorkspaceService<NetcruxTabPayload>`] backed by
/// [`NetcruxWorkspaceCodec`].
class NetcruxWorkspaceNotifier extends WorkspaceNotifier<NetcruxTabPayload> {
  /// Creates the notifier. Production code calls the no-arg form via
  /// [`netcruxWorkspaceProvider`]; tests pass [service] to wire a faked /
  /// temp-directory-backed service.
  NetcruxWorkspaceNotifier({
    WorkspaceService<NetcruxTabPayload>? service,
    super.autoSaveDebounce,
    this.restoreGate,
  }) : super(service: service ?? _defaultService());

  /// Replaces the settings-backed launch gate, for the same reason [service]
  /// is injectable.
  ///
  /// A widget test that fakes the workspace runs inside `flutter_test`'s
  /// fake-async zone, where the settings read's platform-channel reply is
  /// delivered on the *real* event loop: awaiting the workspace future before
  /// the first pump would then wait forever. Passing `() async => true` keeps
  /// such a test on the pre-gate launch path instead of forcing it to stub the
  /// whole settings stack — which would resolve `appSettingsProvider` and
  /// re-seed unrelated state such as the panel layout mid-test.
  final Future<bool> Function()? restoreGate;

  /// Guards `workspace.restored` against the notifier's own rebuilds. `build`
  /// re-runs whenever a watched dependency changes; the *restore* it counts
  /// happens once per process, so without this a settings change would inflate
  /// the launch counter.
  bool _emittedRestored = false;

  /// Records through the seam **resolved now**, never through one captured at
  /// [build].
  ///
  /// It used to be a field, resolved once per build, on the reasoning that a
  /// rebuild must not leave events going to a disposed container and that
  /// `record` stays allocation-free on the no-op path. The first half is
  /// handled here by `ref.mounted`; the second was never at risk, since the
  /// read is a map lookup and the no-op's `record` is still the same empty
  /// method. What the field *did* cost is the reason it is gone:
  /// `telemetryServiceProvider` is not constant for the life of a session. The
  /// consent store publishes `unset` synchronously and reads the persisted
  /// value back asynchronously, so at the moment this notifier builds — a cold
  /// start — the gate has not seen the user's stored answer yet and resolves
  /// the no-op. Caching that froze the first frame's verdict for the whole
  /// session.
  void _emit(String name, [Map<String, Object?>? properties]) {
    if (!ref.mounted) return;
    ref
        .read(telemetryServiceProvider)
        .record(TelemetryEvent(name, properties: properties));
  }

  /// Restores the workspace, then surfaces any corruption-recovery
  /// signal from the load into [workspaceRecoveryNoticeProvider] so a
  /// launch-time widget can show a localized "could not restore your
  /// workspace" notice. Otherwise a pass-through — the inherited `build` does
  /// the actual `WorkspaceService.load` — plus the one-shot
  /// `workspace.restored` counter.
  @override
  Future<Workspace<NetcruxTabPayload>> build() async {
    final workspace = await super.build();
    final recovery = service.takeRecovery();
    if (recovery != null) {
      ref.read(workspaceRecoveryNoticeProvider.notifier).report(recovery);
    }
    if (!_emittedRestored) {
      _emittedRestored = true;
      _emit('workspace.restored', <String, Object?>{
        'tabs': workspace.tabs.length,
        'panes': workspace.panes.length,
      });
    }
    return workspace;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Telemetry-bearing overrides of package methods
  //
  // Each override guards on whether the mutation actually happened, because the
  // package's methods are no-op-safe: `closePane` on a single-pane workspace and
  // `moveTabToPane` onto the pane a tab already occupies both return without
  // changing anything, and a counter that fires on those is measuring keystrokes
  // rather than workspace shape.
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Future<TabId> openTab({
    required String displayName,
    required NetcruxTabPayload payload,
    PaneId? paneId,
    bool dedupe = true,
  }) async {
    final before = (await future).tabs.length;
    final tabId = await super.openTab(
      displayName: displayName,
      payload: payload,
      paneId: paneId,
      dedupe: dedupe,
    );
    final ws = state.value;
    // Deduped opens re-activate an existing tab instead of creating one. That
    // is a tab *switch*, not a tab open — reporting it would make `tab.opened`
    // count re-opening the same file from the recent list, which is a different
    // behaviour with a different answer.
    if (ws != null && ws.tabs.length > before) {
      _emit('tab.opened', <String, Object?>{
        'tabs': ws.tabs.length,
        'panes': ws.panes.length,
      });
    }
    return tabId;
  }

  @override
  Future<PaneId> splitPaneRight() async {
    final before = (await future).panes.length;
    final paneId = await super.splitPaneRight();
    // Already split → the package returns the existing sibling and changes
    // nothing.
    if ((state.value?.panes.length ?? before) > before) _emit('pane.split');
    return paneId;
  }

  @override
  Future<void> closePane(PaneId paneId) async {
    final before = await future;
    final willClose =
        before.panes.length >= 2 && before.panes.any((p) => p.id == paneId);
    await super.closePane(paneId);
    if (willClose) _emit('pane.closed');
  }

  @override
  Future<void> moveTabToPane(TabId tabId, PaneId targetPane) async {
    final before = await future;
    final willMove =
        before.panes.any((p) => p.id == targetPane) &&
        before.tabs.any((t) => t.id == tabId && t.paneId != targetPane);
    await super.moveTabToPane(tabId, targetPane);
    if (willMove) _emit('tab.dragged_to_pane');
  }

  @override
  Future<void> saveAs(String path) async {
    await super.saveAs(path);
    // After the write, so a failed save is not counted as one. `path` itself
    // never leaves the machine — the event carries no properties at all.
    _emit('workspace.named.saved');
  }

  @override
  Future<Workspace<NetcruxTabPayload>> loadFrom(String path) async {
    final loaded = await super.loadFrom(path);
    _emit('workspace.named.opened', <String, Object?>{
      'tabs': loaded.tabs.length,
      'panes': loaded.panes.length,
    });
    return loaded;
  }

  /// Consults the persisted `restoreTabsOnLaunch` preference before the
  /// framework loads `workspace.json`.
  ///
  /// Returning `false` starts from an empty workspace and leaves the document
  /// untouched on disk, so flipping the preference back on brings the session
  /// back; the file is only overwritten once the user mutates the fresh
  /// workspace.
  ///
  /// Reads the settings **service** rather than awaiting
  /// [`appSettingsProvider.future`]. Awaiting a second async provider from
  /// here hands the launch path to Riverpod's failure retry: a settings load
  /// that throws — no platform channel under a widget test, a plugin that has
  /// not registered yet — leaves that future pending across every retry, so
  /// the workspace never resolves and the app never renders. A plain service
  /// future either completes or throws once, and a throw here defaults to
  /// restoring: losing a session because a *preference* was unreadable is the
  /// worse failure.
  @override
  Future<bool> shouldRestoreOnLaunch() async {
    final injected = restoreGate;
    if (injected != null) return injected();
    try {
      final settings = await ref.read(settingsServiceProvider).load();
      return settings.restoreTabsOnLaunch;
    } on Object {
      return true;
    }
  }

  /// Default service factory — public so consumers (and the
  /// [`workspaceServiceProvider`] override hook) construct an identical
  /// service shape without re-declaring the codec.
  @visibleForTesting
  static WorkspaceService<NetcruxTabPayload> defaultService() =>
      _defaultService();

  static WorkspaceService<NetcruxTabPayload> _defaultService() =>
      WorkspaceService<NetcruxTabPayload>(
        codec: const NetcruxWorkspaceCodec(),
      );
}

/// Root-scope async-notifier provider that owns the active NetCrux
/// workspace.
///
/// Lives at the **root** `ProviderScope`. Consumers — the `PaneHost`,
/// CLI handler, command palette actions, lifecycle observer — `ref.watch`
/// it for state and `ref.read(...notifier)` for mutations. The notifier's
/// `build()` calls `WorkspaceService.load()` so the first observation
/// hydrates the workspace from disk (auto-managed `workspace.json` in
/// `getApplicationSupportDirectory()`).
final AsyncNotifierProvider<
  NetcruxWorkspaceNotifier,
  Workspace<NetcruxTabPayload>
>
netcruxWorkspaceProvider =
    AsyncNotifierProvider<
      NetcruxWorkspaceNotifier,
      Workspace<NetcruxTabPayload>
    >(NetcruxWorkspaceNotifier.new);
