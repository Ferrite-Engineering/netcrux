// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart' show CxpServer;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/services/remote/cxp/cxp_inbound_handler.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';

/// Mounts a [`CxpInboundHandler`] for the running CXP server, lifecycle-
/// scoped to this widget.
///
/// The handler routes `request_highlight` requests into the active
/// tab's per-tab `selectedElementProvider` / `hierarchyTreeProvider`,
/// and shells `request_open_source` requests to the configured editor.
/// Resolution of the active tab happens lazily — every time a request
/// arrives — so the handler picks up tab switches without re-mounting.
///
/// Rendering: invisible — returns [child] verbatim. The widget exists
/// purely to bind the handler's lifecycle to the workspace shell's
/// widget tree.
class CxpInboundListener extends ConsumerStatefulWidget {
  /// Creates the listener wrapping [child].
  const CxpInboundListener({required this.child, super.key});

  /// Subtree the listener wraps.
  final Widget child;

  @override
  ConsumerState<CxpInboundListener> createState() => _CxpInboundListenerState();
}

class _CxpInboundListenerState extends ConsumerState<CxpInboundListener> {
  CxpInboundHandler? _handler;
  CxpServer? _attachedServer;

  void _ensureAttached(CxpServer? server) {
    if (identical(server, _attachedServer)) return;
    unawaited(_handler?.dispose());
    _handler = null;
    _attachedServer = server;
    if (server == null) return;
    _handler = CxpInboundHandler(
      server: server,
      rootContainer: ProviderScope.containerOf(context, listen: false),
      activeTabContainerLookup: _activeTabContainer,
    );
  }

  ProviderContainer? _activeTabContainer() {
    final ws = ref.read(netcruxWorkspaceProvider).value;
    if (ws == null) return null;
    final activeTabId = ws.activeTabId;
    if (activeTabId == null) return null;
    return WorkspaceManagersScope.of(
      context,
    ).tabContainerManager.containerFor(activeTabId);
  }

  @override
  void dispose() {
    unawaited(_handler?.dispose());
    _handler = null;
    _attachedServer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(cxpServerHostProvider).value?.server;
    _ensureAttached(server);
    return widget.child;
  }
}
