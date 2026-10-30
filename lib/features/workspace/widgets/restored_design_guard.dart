// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/workspace/services/restored_tab_project.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

/// Makes sure a tab that names sources in the saved workspace has the design
/// they describe, the first time its content is shown.
///
/// A tab's project lives in the tab's own container, so a tab whose container
/// was created fresh (a workspace restored at launch, whichever way the launch
/// went) holds the empty project and renders the "Open Project..." placeholder
/// with nothing loading, however large the design the tab was saved with.
/// The launch-time push in the workspace screen is the main route; this is the
/// net under it, so that no route can leave a tab with sources and no design.
///
/// Waits a frame before looking, so an open that created the tab and is about
/// to install its own project (with the defines and include paths the payload
/// has no room for) is not raced, and installs nothing when the tab holds a
/// design by then.
class RestoredDesignGuard extends ConsumerStatefulWidget {
  /// Creates the guard around a tab's [child].
  const RestoredDesignGuard({required this.child, super.key});

  /// The tab's content.
  final Widget child;

  @override
  ConsumerState<RestoredDesignGuard> createState() =>
      _RestoredDesignGuardState();
}

class _RestoredDesignGuardState extends ConsumerState<RestoredDesignGuard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_hydrate()));
  }

  Future<void> _hydrate() async {
    if (!mounted) return;
    final TabId tabId;
    try {
      tabId = ref.read(tabIdProvider);
    } on Object {
      // Not inside a per-tab container (a bare test harness): there is no
      // tab, so no payload to restore from.
      return;
    }
    final payload = ref
        .read(netcruxWorkspaceProvider)
        .value
        ?.tabs
        .where((tab) => tab.id == tabId)
        .firstOrNull
        ?.payload;
    if (payload == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await hydrateTabProject(container, payload, isCurrent: () => mounted);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
