// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_recovery_provider.g.dart';

/// Holds the most recent [WorkspaceRecovery] surfaced by the workspace
/// notifier when it quarantined a corrupt `workspace.json` on launch. A
/// launch-time widget watches this to show
/// a localized "your workspace could not be restored" notice, then calls
/// [WorkspaceRecoveryNotice.acknowledge] to dismiss it.
///
/// `null` means no recovery happened (the normal case).
@Riverpod(keepAlive: true)
class WorkspaceRecoveryNotice extends _$WorkspaceRecoveryNotice {
  @override
  WorkspaceRecovery? build() => null;

  /// Records that a corrupt workspace document was quarantined. Called by
  /// `NetcruxWorkspaceNotifier.build` after the first load.
  void report(WorkspaceRecovery recovery) {
    if (identical(state, recovery)) return;
    state = recovery;
  }

  /// Clears the notice once the UI has surfaced it.
  void acknowledge() {
    if (state != null) state = null;
  }
}
