// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mutable root-scope handle on the app's singleton [TabContainerManager].
///
/// The manager cannot be constructed inside a Riverpod provider because it
/// needs the **root** `ProviderContainer` as its parent, and the root
/// container is created by `bootstrap` before any provider has been
/// initialised (see `WorkspaceManagersScope` for the widget-tree half of
/// this constraint). Root-scope *providers* that must reach into the
/// active tab's container — the active-tab action-flags mirror feeding
/// `netcruxActionContextProvider` — cannot use the widget-tree
/// `InheritedWidget` route, so `bootstrap` additionally publishes the
/// manager here immediately after constructing it, before `runApp`.
///
/// [manager] is null only in containers that never ran `bootstrap`
/// (unit tests); consumers must treat that as "no tab available".
class TabContainerManagerHolder {
  /// The app's singleton per-tab container manager, or null before
  /// `bootstrap` publishes it.
  TabContainerManager? manager;
}

/// Root-scope access to the [TabContainerManagerHolder]. The holder
/// instance is stable for the app's lifetime; `bootstrap` sets its
/// [TabContainerManagerHolder.manager] field once, synchronously before
/// `runApp`, so no consumer can observe a transition.
final tabContainerManagerHolderProvider = Provider<TabContainerManagerHolder>(
  (ref) => TabContainerManagerHolder(),
  name: 'tabContainerManagerHolderProvider',
);
