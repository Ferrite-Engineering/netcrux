// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/features/workspace/providers/active_tab_action_flags_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';

/// Builds the [NetcruxActionContext] that every action-discovery surface
/// (menu bar, command palette, toolbar) and the keyboard dispatch path
/// feed to the descriptor selectors in `netcrux_action_descriptors.dart`.
/// Centralizing it here guarantees all surfaces gate on identical state.
///
/// Workspace-level facts (open tab, pane count) come straight from
/// `netcruxWorkspaceProvider`; the per-tab facts come from the
/// `activeTabActionFlagsProvider` root mirror, because this provider
/// lives at the root scope where per-tab providers resolve to their
/// empty root instances. Tests override this provider directly with a
/// literal context to drive a surface into a precise state.
final netcruxActionContextProvider = Provider<NetcruxActionContext>((ref) {
  final workspace = ref.watch(netcruxWorkspaceProvider).value;
  final flags = ref.watch(activeTabActionFlagsProvider);
  return NetcruxActionContext(
    hasOpenTab: workspace?.activeTabId != null,
    hasNetlist: flags.hasNetlist,
    hasSelection: flags.hasSelection,
    hasTraceOverlay: flags.hasTraceOverlay,
    hasXTraceResult: flags.hasXTraceResult,
    comparisonActive: flags.comparisonActive,
    waveformLoaded: flags.waveformLoaded,
    cdcAnalysisPresent: flags.cdcAnalysisPresent,
    resetAnalysisPresent: flags.resetAnalysisPresent,
    fsmFocused: flags.fsmFocused,
    activityColoringActive: flags.activityColoringActive,
    paneCount: workspace?.panes.length ?? 1,
    tabCountInActivePane: workspace == null
        ? 0
        : workspace.tabsForPane(workspace.activePaneId).length,
    // The browser is the build that cannot elaborate; one seam decides both,
    // so a test that sets it gets the whole browser shape.
    isBrowser: !ref.watch(hdlElaborationSupportedProvider),
  );
}, name: 'netcruxActionContextProvider');
