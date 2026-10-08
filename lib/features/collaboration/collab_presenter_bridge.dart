// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';
import 'package:netcrux/features/collaboration/collab_follow_detached_provider.dart';
import 'package:netcrux/features/collaboration/collab_presence_publisher.dart';
import 'package:netcrux/features/collaboration/collab_view_degradation_provider.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/services/collaboration/netlist_fingerprint.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

/// How long a presenter's camera has to settle before it is published. A pan
/// or a wheel zoom changes the camera every frame; one frame per quiet burst
/// is what the room needs.
const Duration kCollabPresenterCameraDebounce = Duration(milliseconds: 100);

/// Presenter mode for one tab: publishes what the presenter shows, and has a
/// follower's tab show it.
///
/// Mounted inside each tab's provider scope (around the tab's content), so
/// every read below is this tab's scope, camera and trace. Only the
/// **active** tab takes part: the presenter shares the design they are
/// looking at, and a follower follows in the tab they are looking at. A tab
/// that becomes active joins in at once — it publishes, or catches up with the
/// presenter.
///
/// * **Presenter.** The scope, the trace overlay and the analysis panel at
///   the front of the right dock are published as they change; the camera
///   after [kCollabPresenterCameraDebounce] of quiet. The
///   camera travels as a design-space centre and a zoom, so every follower
///   frames the same place whatever the size of their window.
/// * **Follower.** The presenter's scope is navigated to and their camera
///   framed, on this tab's own state — the same soft-follow WaveCrux applies
///   to its viewport. The presenter's trace and selection are drawn as an
///   overlay by `collabPresenceOverlay` and never written into this tab. The
///   presenter's panel is brought to the front of the follower's dock, over
///   the follower's own analysis state — a Pro panel only where the follower
///   has Pro — and closed again when the presenter moves on or the session
///   ends, if it was the session that opened it.
/// * **Soft-follow.** A pan, a zoom or a change of scope by the follower is a
///   glance away, not a departure: it sets [collabFollowDetachedProvider],
///   which stops the presenter's view being applied until the follower
///   resumes. The presenter is unchanged and the session goes on.
///
/// Also announces this tab's scope and selection when a session admits us or
/// the tab becomes active. The tab content announces scope only when it
/// changes, so without this a participant who joined while already looking at
/// a design would report no scope until they moved.
///
/// Inert outside a session: the open-core collaboration service never starts
/// one, so in an open-core build this widget only passes [child] through.
class CollabPresenterBridge extends ConsumerStatefulWidget {
  /// Wraps [child], the tab's content.
  const CollabPresenterBridge({required this.child, super.key});

  /// The tab content.
  final Widget child;

  @override
  ConsumerState<CollabPresenterBridge> createState() =>
      _CollabPresenterBridgeState();
}

class _CollabPresenterBridgeState extends ConsumerState<CollabPresenterBridge> {
  Timer? _cameraDebounce;

  /// The presenter view last applied to this tab, as a follower. A scope
  /// change that does not match it is the follower's own.
  SchematicCollabPresenterView? _lastApplied;

  /// The view last published, as the presenter. Republishing an unchanged
  /// view is traffic nobody needs.
  SchematicCollabPresenterView? _lastPublished;

  /// Whether this tab has announced itself in the current session.
  bool _announced = false;

  /// Panels this session opened on the follower's behalf. Closed again when
  /// the presenter moves on from them or the session ends, so following leaves
  /// the follower's own dock as it found it.
  final Set<AnalysisPanelKind> _sessionOpenedPanels = {};

  @override
  void dispose() {
    _cameraDebounce?.cancel();
    super.dispose();
  }

  /// This tab's id, or `null` when mounted outside a tab container (a host
  /// with a single canvas, which is then always the one on screen).
  late final TabId? _tabId = _readTabId();

  TabId? _readTabId() {
    try {
      return ref.read(tabIdProvider);
    } on Object {
      return null;
    }
  }

  bool get _isActiveTab {
    final tab = _tabId;
    if (tab == null) return true;
    return ref.read(netcruxWorkspaceProvider).value?.activeTabId == tab;
  }

  SchematicCollabSessionState? get _session {
    final session = ref.read(schematicCollabSessionProvider).value;
    if (session == null || session.isAwaitingAdmission) return null;
    return session;
  }

  @override
  Widget build(BuildContext context) {
    if (_tabId != null) {
      ref.listen(netcruxWorkspaceProvider, (previous, next) {
        final was = previous?.value?.activeTabId;
        final now = next.value?.activeTabId;
        if (was != now && _isActiveTab) _onBecameActive();
      });
    }
    ref
      ..listen(schematicCollabSessionProvider, (previous, next) {
        _onSession(previous?.value, next.value);
      })
      ..listen(collabFollowDetachedProvider, (previous, detached) {
        if (!detached) _applyLatest();
      })
      ..listen(hierarchyTreeProvider, (previous, next) => _onScope(next))
      ..listen(viewportTransformProvider, (previous, next) => _onCamera())
      ..listen(traceOverlayProvider, (previous, next) => _onTrace())
      ..listen(effectiveRightDockTabProvider, (previous, next) => _onTrace());
    return widget.child;
  }

  // ── session lifecycle ──────────────────────────────────────────────────────

  void _onSession(
    SchematicCollabSessionState? previous,
    SchematicCollabSessionState? next,
  ) {
    if (next == null) {
      _announced = false;
      _lastApplied = null;
      _lastPublished = null;
      _cameraDebounce?.cancel();
      _closeSessionPanels(except: null);
      ref.read(collabFollowDetachedProvider.notifier).resume();
      return;
    }
    if (next.isAwaitingAdmission || !_isActiveTab) return;
    if (!_announced) _announce();

    if (next.isLocalPresenter) {
      final becamePresenter =
          previous == null ||
          previous.isAwaitingAdmission ||
          !previous.isLocalPresenter;
      if (becamePresenter) {
        // Whoever presents drives rather than follows.
        ref.read(collabFollowDetachedProvider.notifier).resume();
        _lastPublished = null;
        _publish();
      }
      return;
    }
    if (next.presenterView != previous?.presenterView ||
        next.effectivePresenterId != previous?.effectivePresenterId) {
      _applyLatest();
    }
  }

  void _onBecameActive() {
    final session = _session;
    if (session == null) return;
    _announce();
    if (session.isLocalPresenter) {
      _lastPublished = null;
      _publish();
    } else {
      _applyLatest();
    }
  }

  /// Tells the room which scope and selection this tab is showing.
  void _announce() {
    _announced = true;
    final service = ref.read(schematicCollaborationServiceProvider);
    final model = ref.read(loadedNetlistProvider).value;
    final scopePath = collabScopePath(ref.read(hierarchyTreeProvider).selected);
    service
      ..announceScope(
        scopePath: scopePath,
        netlistContentHash: model == null ? null : netlistFingerprint(model),
      )
      ..updateSelection(
        scopePath: scopePath,
        elementIds: collabElementIds(ref.read(selectedElementProvider)),
      );
  }

  // ── presenter (outbound) ───────────────────────────────────────────────────

  bool get _presenting {
    final session = _session;
    return session != null && session.isLocalPresenter && _isActiveTab;
  }

  bool get _following {
    final session = _session;
    return session != null && !session.isLocalPresenter && _isActiveTab;
  }

  void _publish() {
    _cameraDebounce?.cancel();
    if (!_presenting) return;
    final camera = ref.read(viewportTransformProvider.notifier);
    final view = collabPresenterView(
      scope: ref.read(hierarchyTreeProvider).selected,
      center: camera.designCenter,
      zoom: ref.read(viewportTransformProvider).zoom,
      trace: ref.read(traceOverlayProvider),
      analysisPanel: _frontPanel(),
    );
    if (view == _lastPublished) return;
    _lastPublished = view;
    ref.read(schematicCollaborationServiceProvider).updatePresenterView(view);
  }

  void _onScope(HierarchyTreeState next) {
    if (_presenting) {
      _publish();
      return;
    }
    if (!_following) return;
    final applied = _lastApplied;
    // A scope the presenter did not take us to is the follower's own
    // navigation. Compared against what was applied rather than guarded by a
    // flag, so it holds however the tree's notification is scheduled.
    if (applied != null &&
        collabScopePath(next.selected) != applied.scopePath) {
      ref.read(collabFollowDetachedProvider.notifier).detach();
    }
  }

  void _onCamera() {
    if (_presenting) {
      _cameraDebounce?.cancel();
      _cameraDebounce = Timer(kCollabPresenterCameraDebounce, _publish);
      return;
    }
    if (!_following) return;
    // Only a pan or a zoom is a glance away. A fit when a layout lands, a
    // restore of the presenter's camera, a window resize: the program placing
    // the camera, not the follower moving it.
    if (ref.read(viewportTransformProvider.notifier).lastChangeWasGesture) {
      ref.read(collabFollowDetachedProvider.notifier).detach();
    }
  }

  void _onTrace() {
    if (_presenting) _publish();
  }

  // ── follower (inbound) ─────────────────────────────────────────────────────

  /// Navigates this tab to the presenter's scope and camera, unless the
  /// follower is detached.
  void _applyLatest() {
    final session = _session;
    if (session == null || !_following) return;
    if (ref.read(collabFollowDetachedProvider)) return;
    final view = session.presenterView;
    if (view == null) return;
    _applyPanel(analysisPanelKindNamed(view.analysisPanel));
    final tree = ref.read(hierarchyTreeProvider);
    if (tree.model == null) return;
    _lastApplied = view;

    final cameraNotifier = ref.read(viewportTransformProvider.notifier);
    final camera = view.camera;
    final target = camera == null
        ? null
        : cameraNotifier.transformCenteredOn(
            Offset(camera.centerX, camera.centerY),
            camera.zoom,
          );
    if (view.scopePath != collabScopePath(tree.selected)) {
      final path = collabScopeSegments(view.scopePath);
      // The camera is reinstated when the new scope's layout lands, instead
      // of the fit a scope change otherwise gets.
      if (target != null) cameraNotifier.requestRestore(path, target);
      ref.read(hierarchyTreeProvider.notifier).selectByPath(path);
      return;
    }
    if (target != null && target != ref.read(viewportTransformProvider)) {
      cameraNotifier.restore(target);
    }
  }

  // ── the analysis panel ─────────────────────────────────────────────────────

  /// The analysis panel at the front of the right dock, or `null`.
  AnalysisPanelKind? _frontPanel() {
    final tab = ref.read(effectiveRightDockTabProvider);
    if (!tab.startsWith(kRightDockAnalysisPrefix)) return null;
    return analysisPanelKindNamed(
      tab.substring(kRightDockAnalysisPrefix.length),
    );
  }

  /// Brings the presenter's panel to the front of this follower's dock, over
  /// the follower's own analysis state.
  ///
  /// A Pro panel opens only where this build and licence include Pro:
  /// following a presenter is not a way to get a panel your edition does not
  /// have, and `collabDegradedPanelProvider` tells the follower what they are
  /// missing instead.
  void _applyPanel(AnalysisPanelKind? kind) {
    _closeSessionPanels(except: kind);
    if (kind == null) return;
    if (kind.requiresPro && !ref.read(collabProPanelsAvailableProvider)) {
      return;
    }
    final dock = ref.read(analysisDockProvider.notifier);
    if (!dock.isOpen(kind)) _sessionOpenedPanels.add(kind);
    dock.open(kind);
  }

  void _closeSessionPanels({required AnalysisPanelKind? except}) {
    final dock = ref.read(analysisDockProvider.notifier);
    for (final kind in _sessionOpenedPanels.toList()) {
      if (kind == except) continue;
      _sessionOpenedPanels.remove(kind);
      dock.close(kind);
    }
  }
}
