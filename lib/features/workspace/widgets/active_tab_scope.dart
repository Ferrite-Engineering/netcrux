// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';

// NOTE: this file used to also define `ActiveTabScope`, a widget that
// wrapped its child in a second `UncontrolledProviderScope` over the
// active tab's per-tab container. That widget was REMOVED on purpose:
// mounting a second `UncontrolledProviderScope` over a container that
// `PaneHost` already scopes registers a second Flutter vsync on the
// container's provider scheduler in a subtree that is a *sibling* of the
// tab's content. Riverpod schedules its deferred-refresh task on every
// registered vsync, the shallowest scope builds first, and flushing the
// tab's derived providers inside that sibling scope's build marked the
// tab-content listeners (status bar / hierarchy tree / diagnostics /
// inspector) dirty mid-build — the "setState() or markNeedsBuild()
// called during build" FlutterErrors seen on launch. Widgets that need
// the active tab's state from outside `PaneHost` should either read the
// container imperatively ([ActiveTabContainerRef.activeTabContainerOrNull])
// or use a root-scope mirror provider (`activeTabActionFlagsProvider`).
// Do not reintroduce a persistent second scope over a per-tab container.

/// Helper extension on [`WidgetRef`] that resolves the active tab's
/// per-tab `ProviderContainer`. Returns `null` when no tab is active.
///
/// Used by command-palette / keyboard-shortcut dispatchers that need to
/// mutate the active tab's per-tab state from a widget that lives
/// OUTSIDE the active tab's [`UncontrolledProviderScope`].
extension ActiveTabContainerRef on WidgetRef {
  /// Looks up the active tab's container via the supplied [context]'s
  /// [`WorkspaceManagersScope`]. Returns `null` when no tab is active.
  ///
  /// Throws when no [`WorkspaceManagersScope`] is mounted above the
  /// [context] — see [`WorkspaceManagersScope.of`].
  ProviderContainer? activeTabContainerOrNull(BuildContext context) {
    final ws = read(netcruxWorkspaceProvider).value;
    if (ws == null) return null;
    final activeTabId = ws.activeTabId;
    if (activeTabId == null) return null;
    return WorkspaceManagersScope.of(
      context,
    ).tabContainerManager.containerFor(activeTabId);
  }
}
