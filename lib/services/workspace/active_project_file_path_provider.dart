// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

/// Reactive provider exposing the active tab's
/// [`NetcruxTabPayload.projectFilePath`] (or `null` when no tab is active or
/// the active tab was opened from a source-file list rather than a
/// `.netcrux-project` file).
///
/// Consumed by Pro-only features that need per-project state — most
/// notably the Pro custom-cell-symbol registry, which resolves its
/// per-project storage directory (`<project-root>/.netcrux-symbols/`)
/// from this value. When the user switches tabs or loads a different
/// project, this provider emits a new value and downstream listeners
/// (e.g. the symbol registry) rebind their per-project state.
///
/// Returns the active pane's active tab's `projectFilePath`. Returns
/// `null` when:
///
///   * The workspace is still loading (initial `AsyncValue.loading`),
///   * The workspace failed to load (`AsyncValue.error`),
///   * No tabs are open,
///   * The active tab's payload has no `projectFilePath` (e.g. tab was
///     opened from a raw source-file list or a `.netcrux` session import).
///
/// Open-core defines this provider so the per-tab payload schema lives in
/// one place; Pro overlays read it. Mocking in tests is straightforward
/// via `.overrideWithValue(null)` for the no-project case or
/// `.overrideWithValue('/path/to/project.netcrux-project')` for the
/// project-loaded case.
final activeProjectFilePathProvider = Provider<String?>(
  (ref) {
    final wsAsync = ref.watch(netcruxWorkspaceProvider);
    final ws = wsAsync.asData?.value;
    if (ws == null) return null;
    final activeTabId = ws.activeTabId;
    if (activeTabId == null) return null;
    WorkspaceTab<NetcruxTabPayload>? activeTab;
    for (final t in ws.tabs) {
      if (t.id == activeTabId) {
        activeTab = t;
        break;
      }
    }
    if (activeTab == null) return null;
    final path = activeTab.payload.projectFilePath;
    if (path == null || path.isEmpty) return null;
    return path;
  },
  name: 'activeProjectFilePathProvider',
);
