// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/shortcuts/action_category.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptor.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptors.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/workspace/providers/netcrux_action_context_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// NetCrux's binding of the shared [CruxToolbar] to its own action catalog.
///
/// Everything structural — geometry, the `[common] │ [specific]` split, the
/// overflow slot and its edge fade, live-binding tooltips, per-action keys and
/// the semantics region — lives in `crux_toolbar` so all four products behave
/// identically. This widget supplies only NetCrux's item lists and wires
/// enablement to the descriptor table, exactly as the menu bar and command
/// palette do.
class NetcruxToolbar extends ConsumerWidget {
  /// Creates the NetCrux toolbar.
  const NetcruxToolbar({required this.onAction, super.key});

  /// Dispatches a selected action through the shared handler path.
  final void Function(NetcruxAction) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final ctx = ref.watch(netcruxActionContextProvider);
    final bindings = ref.watch(shortcutBindingsProvider);
    // Dock-aware glyph: lit only when the CXP tab is the one on screen.
    final crossProbeVisible = ref.watch(crossProbeShowingProvider);
    // The peer count rides the cross-probe button as a badge, so "is anyone
    // connected?" is answerable without opening the panel — the question the
    // descriptor comments explicitly wrestle with when they keep the panel
    // openable at zero peers.
    final peerCount = ref.watch(cxpPeersProvider).value?.length ?? 0;

    return CruxToolbar<NetcruxAction>(
      common: _visibleItems(ctx, [
        CruxToolbarButtonItem(
          action: NetcruxAction.openProject,
          icon: Icons.folder_open_outlined,
          tooltip: l10n.actionOpenProject,
        ),
        CruxToolbarButtonItem(
          action: NetcruxAction.saveSession,
          icon: Icons.save_outlined,
          tooltip: l10n.actionSaveSession,
        ),
        CruxToolbarButtonItem(
          action: NetcruxAction.closeProject,
          icon: Icons.close,
          tooltip: l10n.actionCloseProject,
        ),
        const CruxToolbarSeparatorItem(),
        CruxToolbarButtonItem(
          action: NetcruxAction.openSearch,
          icon: Icons.search,
          tooltip: l10n.actionOpenSearch,
        ),
        CruxToolbarButtonItem(
          action: NetcruxAction.showCrossProbePanel,
          icon: Icons.sensors_outlined,
          selectedIcon: Icons.sensors,
          isSelected: crossProbeVisible,
          badgeCount: peerCount,
          tooltip: l10n.toolbarToggleCrossProbe,
        ),
        CruxToolbarButtonItem(
          action: NetcruxAction.openSettings,
          icon: Icons.settings_outlined,
          tooltip: l10n.actionOpenSettings,
        ),
      ]),
      specific: _visibleItems(ctx, [
        CruxToolbarButtonItem(
          action: NetcruxAction.openSourceFiles,
          icon: Icons.note_add_outlined,
          tooltip: l10n.actionOpenSourceFiles,
        ),
        CruxToolbarButtonItem(
          action: NetcruxAction.openNetlistJson,
          icon: Icons.data_object,
          tooltip: l10n.actionOpenNetlistJson,
        ),
        const CruxToolbarSeparatorItem(),
        CruxToolbarButtonItem(
          action: NetcruxAction.zoomIn,
          icon: Icons.zoom_in,
          tooltip: l10n.actionZoomIn,
        ),
        CruxToolbarButtonItem(
          action: NetcruxAction.zoomOut,
          icon: Icons.zoom_out,
          tooltip: l10n.actionZoomOut,
        ),
        CruxToolbarButtonItem(
          action: NetcruxAction.zoomFitAll,
          icon: Icons.fit_screen_outlined,
          tooltip: l10n.actionZoomFitAll,
        ),
        CruxToolbarButtonItem(
          action: NetcruxAction.zoomToSelection,
          icon: Icons.center_focus_strong_outlined,
          tooltip: l10n.actionZoomToSelection,
        ),
        const CruxToolbarSeparatorItem(),
        CruxToolbarButtonItem(
          action: NetcruxAction.jumpToTop,
          icon: Icons.vertical_align_top,
          tooltip: l10n.actionJumpToTop,
        ),
        CruxToolbarButtonItem(
          action: NetcruxAction.popOutScope,
          icon: Icons.arrow_upward,
          tooltip: l10n.actionPopOutScope,
        ),
        const CruxToolbarSeparatorItem(),
        // Fan-in / fan-out / clear are the core netlist-tracing verbs and were
        // menu-only: three near-identical buttons would crowd the strip, so
        // they share one split slot. Tap runs the faced variant; long-press,
        // right-click, or the corner triangle offers the siblings.
        CruxToolbarSplitItem(
          id: 'trace',
          tooltip: l10n.toolbarTraceCluster,
          variants: [
            CruxToolbarButtonItem(
              action: NetcruxAction.showFanin,
              icon: Icons.call_received,
              tooltip: l10n.actionShowFanin,
            ),
            CruxToolbarButtonItem(
              action: NetcruxAction.showFanout,
              icon: Icons.call_made,
              tooltip: l10n.actionShowFanout,
            ),
            CruxToolbarButtonItem(
              action: NetcruxAction.clearOverlay,
              icon: Icons.layers_clear_outlined,
              tooltip: l10n.actionClearOverlay,
            ),
          ],
        ),
      ]),
      isEnabled: (action) => isActionEnabled(action, ctx),
      onAction: onAction,
      shortcutOf: (action) => bindings[action],
      semanticsLabel: l10n.accessibilityToolbarRegion,
      overflow: CruxToolbarOverflowMenu<NetcruxAction>(
        groups: [
          for (final entry in groupedActionsFor(
            NetcruxActionSurface.menu,
            ctx,
          ).entries)
            if (entry.key != ActionCategory.app)
              CruxOverflowGroup<NetcruxAction>(
                label: entry.key.label(l10n),
                actions: entry.value,
              ),
        ],
        labelOf: (action) => action.label(l10n),
        isEnabled: (action) => isActionEnabled(action, ctx),
        shortcutOf: (action) => bindings[action],
        onAction: onAction,
        tooltip: l10n.toolbarOverflowActions,
      ),
    );
  }

  /// [items] without the buttons whose action is hidden under [ctx] — the
  /// browser build's desktop-only actions — and without the separators that
  /// would then lead, trail, or double up.
  static List<CruxToolbarItem<NetcruxAction>> _visibleItems(
    NetcruxActionContext ctx,
    List<CruxToolbarItem<NetcruxAction>> items,
  ) {
    final kept = <CruxToolbarItem<NetcruxAction>>[
      for (final item in items)
        if (item is! CruxToolbarButtonItem<NetcruxAction> ||
            isActionVisibleIn(item.action, NetcruxActionSurface.toolbar, ctx))
          item,
    ];
    final result = <CruxToolbarItem<NetcruxAction>>[];
    for (final item in kept) {
      final isSeparator = item is CruxToolbarSeparatorItem<NetcruxAction>;
      if (isSeparator &&
          (result.isEmpty ||
              result.last is CruxToolbarSeparatorItem<NetcruxAction>)) {
        continue;
      }
      result.add(item);
    }
    if (result.isNotEmpty &&
        result.last is CruxToolbarSeparatorItem<NetcruxAction>) {
      result.removeLast();
    }
    return result;
  }
}
