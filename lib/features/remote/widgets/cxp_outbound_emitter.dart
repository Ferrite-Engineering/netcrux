// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/services/remote/cxp/cxp_outbound_emitter_controller.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';

/// Mounts the CXP outbound emitter against the **active pane's active
/// tab's** per-tab `ProviderContainer`, remounting when the active tab
/// changes.
///
/// The container is resolved here and handed to [CxpOutboundEmitter]
/// directly — deliberately NOT via an `UncontrolledProviderScope` (the
/// former `ActiveTabScope`). Mounting a second `UncontrolledProviderScope`
/// over a container that `PaneHost` already scopes registers a second
/// Flutter vsync on that container's provider scheduler, in a subtree that
/// is a *sibling* of the tab's content. Riverpod schedules its
/// deferred-refresh task on every registered vsync and the shallowest one
/// builds first — so the flush of the tab's derived providers (e.g. the
/// elaboration pipeline resolving on launch) ran inside this sibling
/// scope's build, and notifying the tab-content listeners (status bar,
/// hierarchy tree, diagnostics drawer, inspector) tripped
/// "setState() or markNeedsBuild() called during build" — the launch
/// FlutterErrors that surfaced with the shared-chrome adoption. The
/// emitter's controller only needs the container object (it uses manual
/// `container.listen` subscriptions and watches nothing from the widget
/// tree), so no scope is needed at all.
///
/// When no tab is active (empty workspace) this renders nothing — the
/// outer `PaneHost` shows the empty-canvas state and there is no
/// selection to broadcast.
class ActiveTabCxpEmitter extends ConsumerWidget {
  /// Creates the active-tab-following CXP emitter mount.
  const ActiveTabCxpEmitter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTabId = ref.watch(
      netcruxWorkspaceProvider.select((ws) => ws.value?.activeTabId),
    );
    if (activeTabId == null) return const SizedBox.shrink();
    final tabs = WorkspaceManagersScope.of(context).tabContainerManager;
    final container = tabs.containerFor(activeTabId);
    // Key by tab id so switching tabs disposes and remounts the emitter:
    // the controller resubscribes against the new tab's container and
    // never leaks the previous tab's selection.
    return CxpOutboundEmitter(
      key: ValueKey<String>('active-tab-cxp-${activeTabId.value}'),
      container: container,
      child: const SizedBox.shrink(),
    );
  }
}

/// Thin widget shim around [`CxpOutboundEmitterController`].
///
/// Mounted by [ActiveTabCxpEmitter], which resolves the focused tab's
/// per-tab container and keys this widget by tab id. When the user
/// switches tabs this widget disposes and remounts, the controller
/// resubscribes against the new tab's container — so the emitter always
/// tracks the focused tab and never leaks the previous tab's selection.
///
/// Rendering: invisible — returns [child] verbatim. The widget exists
/// purely so the controller's lifecycle is bound to the workspace
/// shell's widget tree.
class CxpOutboundEmitter extends ConsumerStatefulWidget {
  /// Creates the emitter wrapping [child].
  const CxpOutboundEmitter({
    required this.container,
    required this.child,
    super.key,
  });

  /// The per-tab container whose selection/trace state the controller
  /// subscribes to.
  final ProviderContainer container;

  /// Subtree the emitter wraps and returns verbatim.
  final Widget child;

  @override
  ConsumerState<CxpOutboundEmitter> createState() => _CxpOutboundEmitterState();
}

class _CxpOutboundEmitterState extends ConsumerState<CxpOutboundEmitter> {
  CxpOutboundEmitterController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = CxpOutboundEmitterController(widget.container);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
