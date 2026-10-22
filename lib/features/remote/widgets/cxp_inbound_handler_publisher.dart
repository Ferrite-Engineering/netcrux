// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/remote/providers/cxp_active_document_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_inbound_handler_holder_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/cxp_inbound_handler.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';

/// Publishes NetCrux's [NetcruxCxpRequestHandler] for the lifetime of this
/// widget, so peers' requests reach the workspace.
///
/// The handler routes `request_highlight` requests into the active tab's
/// per-tab `selectedElementProvider` / `hierarchyTreeProvider`, shells
/// `request_open_source` requests to the configured editor and opens
/// `request_open_artifact` designs into the active tab. The active tab is
/// resolved every time a request arrives, so the handler follows tab switches
/// without being rebuilt.
///
/// Rendering: invisible, it returns [child] verbatim. The widget exists to bind
/// the handler's lifecycle to the workspace shell's widget tree.
class CxpInboundHandlerPublisher extends ConsumerStatefulWidget {
  /// Creates the publisher wrapping [child].
  const CxpInboundHandlerPublisher({required this.child, super.key});

  /// Subtree the publisher wraps.
  final Widget child;

  @override
  ConsumerState<CxpInboundHandlerPublisher> createState() =>
      _CxpInboundHandlerPublisherState();
}

class _CxpInboundHandlerPublisherState
    extends ConsumerState<CxpInboundHandlerPublisher> {
  NetcruxCxpRequestHandler? _handler;
  ProviderContainer? _container;

  @override
  void initState() {
    super.initState();
    // Published after the first frame: a provider cannot be modified while the
    // tree is building.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _handler != null) return;
      final container = ProviderScope.containerOf(context, listen: false);
      final handler = NetcruxCxpRequestHandler(
        rootContainer: container,
        activeTabContainerLookup: _activeTabContainer,
        notice: _notice,
      );
      _container = container;
      _handler = handler;
      container.read(netcruxInboundHandlerHolderProvider.notifier).handler =
          handler;
    });
  }

  /// A toast about a request a peer started, in the app's language. The
  /// toast is the context-free one: the request did not come from a gesture
  /// in any widget.
  void _notice(String Function(L10N l10n) message) {
    if (!mounted) return;
    final l10n = Localizations.of<L10N>(context, L10N);
    if (l10n == null) return;
    CruxToasts.showInfo(message(l10n));
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
    final handler = _handler;
    final container = _container;
    _handler = null;
    _container = null;
    if (handler != null) {
      unawaited(handler.dispose());
      // Withdrawn after this frame: a provider cannot be modified while the
      // tree is being torn down, and a container disposed in the meantime
      // (a test ending) has nothing left to withdraw from.
      scheduleMicrotask(() {
        if (container == null) return;
        try {
          container
              .read(netcruxInboundHandlerHolderProvider.notifier)
              .withdraw(handler);
        } on Object {
          // The container was disposed first.
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the active design announced to peers for as long as the
    // workspace is up (CXP §8.1 `active_document`). Listened, not watched:
    // nothing here redraws when it changes.
    ref.listen(cxpActiveDocumentSyncProvider, (_, _) {});
    return widget.child;
  }
}
