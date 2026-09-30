// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/widgets.dart';

/// Inherited holder for the singleton [`TabContainerManager`] and
/// [`PaneContainerManager`] constructed at app startup.
///
/// The managers can't be constructed inside a Riverpod provider because
/// they need the **root** [`ProviderContainer`] as their parent, and the
/// root container is created by [`bootstrap`] before any provider has
/// been initialised. Bootstrap therefore:
///
/// 1. Constructs the root [`ProviderContainer`] with the CLI / web / Pro
///    overrides applied.
/// 2. Constructs [`TabContainerManager`] / [`PaneContainerManager`] using
///    the root container as parent.
/// 3. Wraps the [`UncontrolledProviderScope`]'s child in a
///    [`WorkspaceManagersScope`] so deep widgets (the home-route's
///    `PaneHost`, the tab-bar, command handlers) can reach them via
///    [`WorkspaceManagersScope.of`].
///
/// The managers themselves are stable for the lifetime of the app, so
/// [`updateShouldNotify`] always returns `false` — descendants never need
/// to re-build because of a manager swap.
class WorkspaceManagersScope extends InheritedWidget {
  /// Creates a scope wrapping [child] with the two container managers.
  const WorkspaceManagersScope({
    required this.tabContainerManager,
    required this.paneContainerManager,
    required super.child,
    super.key,
  });

  /// Per-tab `ProviderContainer` manager for the workspace.
  final TabContainerManager tabContainerManager;

  /// Per-pane `ProviderContainer` manager for the workspace.
  final PaneContainerManager paneContainerManager;

  /// Returns the nearest [`WorkspaceManagersScope`] ancestor. Throws when
  /// no scope is mounted — bootstrap is required to wrap every route with
  /// one. Use [`maybeOf`] for the optional lookup variant.
  static WorkspaceManagersScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(
      scope != null,
      'WorkspaceManagersScope not found above this context — '
      'bootstrap is responsible for wrapping the root.',
    );
    return scope!;
  }

  /// Returns the nearest [`WorkspaceManagersScope`] ancestor, or `null`
  /// when none exists.
  static WorkspaceManagersScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WorkspaceManagersScope>();
  }

  @override
  bool updateShouldNotify(WorkspaceManagersScope oldWidget) => false;
}
