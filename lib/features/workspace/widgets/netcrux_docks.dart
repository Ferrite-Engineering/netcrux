// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_panel.dart';
import 'package:netcrux/features/inspector/widgets/inspector_panel.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/features/remote/providers/cross_probe_visible_provider.dart';
import 'package:netcrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/x_trace_panel_visible_provider.dart';
import 'package:netcrux/features/viewer/providers/x_trace_result_notifier.dart';
import 'package:netcrux/features/viewer/services/x_trace_controller.dart';
import 'package:netcrux/features/viewer/widgets/x_trace_result_panel.dart';
import 'package:netcrux/features/workspace/widgets/open_core_analysis_panels.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// NetCrux's right dock: Inspector (pinned) · one tab per open analysis
/// panel (on-demand, multi-open) · Cross-Probe (on-demand) · X-Trace
/// (on-demand).
///
/// Replaces `AnalysisDockHost`'s priority chain (Cross-Probe > analysis dock
/// > Inspector) *and* the forced-visibility special case in
/// `NetcruxIdeLayout` — where the right region was held open while an
/// analysis was docked and drag-to-collapse had to guess whether it was
/// closing "the dock" or "the inspector". Under the dock model the region has
/// one visibility flag (`inspectorVisible`), every occupant is a tab, and
/// closing an analysis falls back to the Inspector tab with the region open —
/// the same VSCode semantics as the rest of the suite.
///
/// Mounted per-tab (inside `ProjectTabContent`'s right slot); the presence
/// providers are root-scoped workspace chrome, while the panel *content*
/// reads this tab's per-tab analysis state.
class NetcruxRightDock extends ConsumerWidget {
  /// Creates the right dock.
  const NetcruxRightDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final tabNotifier = ref.read(rightDockTabProvider.notifier);

    final entries = <CruxDockEntry>[
      CruxDockEntry(
        id: kRightDockTabInspector,
        icon: Icons.info_outline,
        label: l10n.dockTabInspector,
        builder: (_) => const InspectorPanel(),
      ),
      // The docked panels — one tab per open panel, in the order opened
      // (CDC beside the diff is what the strip is for).
      // Annotations are open core's; the analyses are the Pro overlay's, and
      // a build without its builder never lists them, because every
      // analysis opener is a no-op there.
      ..._movableEntries(context, ref, region: kDockRegionRight),
    ];

    return CruxDock(
      entries: entries,
      activeId: ref.watch(effectiveRightDockTabProvider),
      onSelect: tabNotifier.select,
      onAutoReveal: tabNotifier.reveal,
      dockId: kDockRegionRight,
      onTabMovedIn: (id, _) => _moveTab(ref, id, kDockRegionRight),
      onCollapse: () => ref
          .read(panelLayoutProvider.notifier)
          .setInspectorVisible(visible: false),
      collapseTooltip: l10n.dockCollapseTooltip,
      collapseDirection: CruxDockCollapseDirection.right,
      semanticsLabel: l10n.accessibilityRightDockRegion,
    );
  }

  static IconData _analysisIcon(AnalysisPanelKind kind) => switch (kind) {
    AnalysisPanelKind.cdc => Icons.sync_alt,
    AnalysisPanelKind.resetDomain => Icons.restart_alt,
    AnalysisPanelKind.fsm => Icons.account_tree_outlined,
    AnalysisPanelKind.fsmResults => Icons.account_tree,
    AnalysisPanelKind.activity => Icons.bar_chart,
    AnalysisPanelKind.diff => Icons.compare_arrows,
    AnalysisPanelKind.source => Icons.code,
    AnalysisPanelKind.annotations => Icons.sticky_note_2_outlined,
  };

  static String _analysisLabel(L10N l10n, AnalysisPanelKind kind) =>
      analysisPanelLabel(l10n, kind);
}

/// The dock-tab title of [kind]: what the panel is called wherever it is
/// named, the dock and a collaborative session's "requires NetCrux Pro"
/// notice alike.
String analysisPanelLabel(L10N l10n, AnalysisPanelKind kind) => switch (kind) {
  AnalysisPanelKind.cdc => l10n.dockTabCdc,
  AnalysisPanelKind.resetDomain => l10n.dockTabResetDomain,
  AnalysisPanelKind.fsm => l10n.dockTabFsm,
  AnalysisPanelKind.fsmResults => l10n.dockTabFsmResults,
  AnalysisPanelKind.activity => l10n.dockTabActivity,
  AnalysisPanelKind.diff => l10n.dockTabDiff,
  AnalysisPanelKind.source => l10n.dockTabSource,
  AnalysisPanelKind.annotations => l10n.dockTabAnnotations,
};

/// NetCrux's left dock: the hierarchy tree, alone and pinned — so the
/// auto-hiding strip renders as a plain "Hierarchy" titled header with the
/// collapse / pop-out cluster, the agreed alternative to an activity rail.
class NetcruxLeftDock extends ConsumerWidget {
  /// Creates the left dock.
  const NetcruxLeftDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return CruxDock(
      entries: [
        CruxDockEntry(
          id: 'hierarchy',
          icon: Icons.account_tree_outlined,
          label: l10n.dockTabHierarchy,
          builder: (_) => const HierarchyTreePanel(),
        ),
      ],
      onSelect: (_) {},
      onCollapse: () => ref
          .read(panelLayoutProvider.notifier)
          .setHierarchyTreeVisible(visible: false),
      collapseTooltip: l10n.dockCollapseTooltip,
      collapseDirection: CruxDockCollapseDirection.left,
      semanticsLabel: l10n.accessibilityLeftDockRegion,
    );
  }
}

/// The bottom dock's pinned Diagnostics tab id. Shared with the
/// `openTabDiagnostics` dispatch, which reveals this tab via
/// [BottomDockTabNotifier.reveal].
const String kBottomDockTabDiagnostics = 'diagnostics';

/// NetCrux's bottom dock: the elaboration-diagnostics drawer, pinned — the
/// suite's "Debug" bottom panel, now with the same titled-header chrome as
/// every other region.
class NetcruxBottomDock extends ConsumerWidget {
  /// Creates the bottom dock.
  const NetcruxBottomDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final hasDiagnostics = ref.watch(elaborationDiagnosticsProvider).isNotEmpty;
    return CruxDock(
      entries: [
        CruxDockEntry(
          id: kBottomDockTabDiagnostics,
          icon: Icons.rule,
          label: l10n.dockTabDiagnostics,
          // Copy-report lives in the strip's action cluster — the drawer's
          // old title row (whose only other content duplicated this tab's
          // label) is gone.
          actions: [
            IconButton(
              icon: const Icon(Icons.copy, size: kCruxDockIconSize),
              tooltip: l10n.elaborationDiagnosticsCopyReport,
              onPressed: hasDiagnostics
                  ? () => unawaited(
                      TabDiagnosticsDrawer.copyReportToClipboard(context, ref),
                    )
                  : null,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: 28,
                height: 28,
              ),
            ),
          ],
          builder: (_) => const TabDiagnosticsDrawer(),
        ),
        // Tabs dragged down from the right dock (analyses / Cross-Probe).
        ..._movableEntries(context, ref, region: kDockRegionBottom),
      ],
      activeId: ref.watch(bottomDockTabProvider),
      onSelect: (id) => ref.read(bottomDockTabProvider.notifier).select(id),
      dockId: kDockRegionBottom,
      onTabMovedIn: (id, _) => _moveTab(ref, id, kDockRegionBottom),
      onCollapse: () => ref
          .read(panelLayoutProvider.notifier)
          .setDiagnosticsVisible(visible: false),
      collapseTooltip: l10n.dockCollapseTooltip,
      semanticsLabel: l10n.accessibilityBottomDockRegion,
    );
  }
}

/// The movable entries (open analyses + Cross-Probe + X-Trace) currently
/// placed in [region], honouring drag overrides. Consumed by BOTH docks.
List<CruxDockEntry> _movableEntries(
  BuildContext context,
  WidgetRef ref, {
  required String region,
}) {
  final l10n = L10N.of(context);
  final placements = ref.watch(dockPlacementsProvider);
  final openKinds = ref.watch(analysisDockProvider);
  final proBuilder = ref.watch(analysisPanelBuilderProvider);
  final crossProbeVisible = ref.watch(crossProbeVisibleProvider);
  final xTraceVisible = ref.watch(xTracePanelVisibleProvider);

  bool placedHere(String id) => (placements[id] ?? kDockRegionRight) == region;

  // Open core builds the Annotations panel itself; every other
  // analysis panel comes from the overlay's builder, so a build without one
  // never lists a tab it cannot fill.
  AnalysisPanelBuilder? builderFor(AnalysisPanelKind kind) =>
      isOpenCoreAnalysisPanel(kind) ? buildOpenCoreAnalysisPanel : proBuilder;

  return <CruxDockEntry>[
    for (final kind in openKinds)
      if (builderFor(kind) case final builder?
          when placedHere(analysisDockTabId(kind)))
        CruxDockEntry(
          id: analysisDockTabId(kind),
          icon: NetcruxRightDock._analysisIcon(kind),
          label: NetcruxRightDock._analysisLabel(l10n, kind),
          movable: true,
          builder: (context) => builder(context, kind),
          onClose: () => ref.read(analysisDockProvider.notifier).close(kind),
        ),
    if (crossProbeVisible && placedHere(kRightDockTabCrossProbe))
      CruxDockEntry(
        id: kRightDockTabCrossProbe,
        icon: Icons.sensors_outlined,
        label: l10n.dockTabCrossProbe,
        movable: true,
        builder: (_) => const NetCruxCrossProbePanel(),
        onClose: () =>
            ref.read(crossProbeVisibleProvider.notifier).set(visible: false),
      ),
    // On-demand and movable, following Cross-Probe rather than the
    // `AnalysisPanelKind` path above: those entries are gated on a non-null
    // Pro builder, which would make an open-core action unreachable in an
    // open-core build and contradict both `showXTracePanel`'s open-core tier
    // and the ARB's promise of an empty panel under the no-op service.
    //
    // `×` clears the VISIBILITY flag only. The result survives, so reopening
    // the panel restores the chain — the distinction the panel's strings
    // encode, where Clear (below) empties the result and leaves the panel up.
    if (xTraceVisible && placedHere(kRightDockTabXTrace))
      CruxDockEntry(
        id: kRightDockTabXTrace,
        icon: Icons.linear_scale,
        label: l10n.xTracePanelTitle,
        movable: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.clear, size: kCruxDockIconSize),
            tooltip: l10n.xTracePanelClearButton,
            // Routes through the shared controller, not an inline clear, so
            // this button and `NetcruxAction.clearXTrace` are one code path —
            // including the overlay clear, which is the half that is easy to
            // forget on a second surface.
            onPressed: ref.watch(xTraceResultProvider).isEmpty
                ? null
                : () => XTraceController.fromContainer(
                    ProviderScope.containerOf(context, listen: false),
                  ).clear(),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
        ],
        builder: (_) => const XTraceResultPanel(),
        onClose: () =>
            ref.read(xTracePanelVisibleProvider.notifier).set(visible: false),
      ),
  ];
}

/// Drop handler: re-home [id] into [region] and reveal it there.
void _moveTab(WidgetRef ref, String id, String region) {
  ref.read(dockPlacementsProvider.notifier).move(id, region);
  if (region == kDockRegionBottom) {
    ref.read(bottomDockTabProvider.notifier).reveal(id);
  } else {
    ref.read(rightDockTabProvider.notifier).reveal(id);
  }
}

/// The bottom dock's active tab id (Diagnostics unless a moved-in tab was
/// revealed). Session-only, like the right dock's.
class BottomDockTabNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Records [id] as the active tab.
  // ignore: use_setters_to_change_properties
  void select(String id) => state = id;

  /// Reveals [id]: records the choice AND opens the bottom region.
  void reveal(String id) {
    state = id;
    unawaited(
      ref
          .read(panelLayoutProvider.notifier)
          .setDiagnosticsVisible(visible: true),
    );
  }
}

/// See [BottomDockTabNotifier].
final bottomDockTabProvider = NotifierProvider<BottomDockTabNotifier, String?>(
  BottomDockTabNotifier.new,
  name: 'bottomDockTabProvider',
);

/// Wraps the IDE layout with the JetBrains-style collapsed-region restore
/// bars (suite panel-reopen model): a hidden region leaves a slim strip of
/// its tab icons along its window edge; a click reopens the region with
/// that tab active.
class NetcruxDockRestoreBars extends ConsumerWidget {
  /// Creates the wrapper. [child] is the `CruxIdeLayout`.
  const NetcruxDockRestoreBars({required this.child, super.key});

  /// The IDE layout being wrapped.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final layout = ref.watch(panelLayoutProvider);
    final notifier = ref.read(panelLayoutProvider.notifier);

    final showLeft = !layout.hierarchyTreeVisible;
    final showRight = !layout.inspectorVisible;
    final showBottom = !layout.diagnosticsVisible;

    // One tree shape whatever is collapsed -- picking the wrapper widget by
    // which regions were collapsed (the bare child, a Column, a Row, a Row
    // around a Column) changed the widget type directly above the IDE
    // layout on every dock toggle, so Flutter discarded and rebuilt the
    // whole layout: every dock, the pane scope, the show/hide animation,
    // and dock scroll positions. See WaveCrux's dock_restore_bars.dart for
    // the incident this mirrors. The bars are keyed so one appearing or
    // vanishing is matched by identity and touches nothing but itself.
    return Row(
      children: [
        if (showLeft)
          CruxDockRestoreBar(
            key: const ValueKey('dockRestoreBar.left'),
            edge: CruxDockCollapseDirection.left,
            entries: [
              CruxDockRestoreEntry(
                id: 'hierarchy',
                icon: Icons.account_tree_outlined,
                label: l10n.dockTabHierarchy,
                onRestore: () =>
                    notifier.setHierarchyTreeVisible(visible: true),
              ),
            ],
            semanticsLabel: l10n.accessibilityLeftDockRegion,
          ),
        Expanded(
          key: const ValueKey('dockRestoreBars.center'),
          child: Column(
            children: [
              Expanded(child: child),
              if (showBottom)
                CruxDockRestoreBar(
                  key: const ValueKey('dockRestoreBar.bottom'),
                  edge: CruxDockCollapseDirection.down,
                  entries: [
                    CruxDockRestoreEntry(
                      id: kBottomDockTabDiagnostics,
                      icon: Icons.rule,
                      label: l10n.dockTabDiagnostics,
                      onRestore: () => unawaited(
                        notifier.setDiagnosticsVisible(visible: true),
                      ),
                    ),
                    for (final entry in _movableEntries(
                      context,
                      ref,
                      region: kDockRegionBottom,
                    ))
                      CruxDockRestoreEntry(
                        id: entry.id,
                        icon: entry.icon,
                        label: entry.label,
                        onRestore: () => ref
                            .read(bottomDockTabProvider.notifier)
                            .reveal(entry.id),
                      ),
                  ],
                  semanticsLabel: l10n.accessibilityBottomDockRegion,
                ),
            ],
          ),
        ),
        if (showRight)
          CruxDockRestoreBar(
            key: const ValueKey('dockRestoreBar.right'),
            edge: CruxDockCollapseDirection.right,
            entries: [
              CruxDockRestoreEntry(
                id: kRightDockTabInspector,
                icon: Icons.info_outline,
                label: l10n.dockTabInspector,
                onRestore: () => ref
                    .read(rightDockTabProvider.notifier)
                    .reveal(kRightDockTabInspector),
              ),
              for (final entry in _movableEntries(
                context,
                ref,
                region: kDockRegionRight,
              ))
                CruxDockRestoreEntry(
                  id: entry.id,
                  icon: entry.icon,
                  label: entry.label,
                  onRestore: () =>
                      ref.read(rightDockTabProvider.notifier).reveal(entry.id),
                ),
            ],
            semanticsLabel: l10n.accessibilityRightDockRegion,
          ),
      ],
    );
  }
}
