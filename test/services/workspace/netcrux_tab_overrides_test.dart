// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/cdc/cdc_severity.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/cdc/providers/cdc_analysis_state_provider.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/source_pane/providers/source_pane_state_provider.dart';
import 'package:netcrux/features/viewer/providers/pane_render_stats.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';

void main() {
  group('netcruxTabOverridesFactory', () {
    test('lists an override for every per-tab provider', () {
      final tabId = TabId.generate();
      final overrides = netcruxTabOverridesFactory(tabId);
      // The factory wires 30 per-tab providers (project + elaboration
      // pipeline including the two derived diagnostics views and the
      // netlist-footprint view + laid-out graph with its layout-timing
      // history + hierarchy + viewer state + the collaboration-presence
      // projection + the reveal-request seam + the scope-flash seam +
      // source-pane state + file watcher + schematic-canvas RepaintBoundary
      // key + CDC analysis state with its four derived views + the
      // annotation state with its store, snapshot, reveal request
      // and canvas markers). When that
      // count changes, update the `docs/ARCHITECTURE.md` inventory and the
      // verification doc.
      expect(overrides, hasLength(30));
    });

    test('two per-tab containers hold independent state', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);

      final tabA = TabId.generate();
      final tabB = TabId.generate();
      final manager = TabContainerManager(
        rootContainer: root,
        overridesFactory: netcruxTabOverridesFactory,
      );
      addTearDown(manager.dispose);
      final containerA = manager.containerFor(tabA);
      final containerB = manager.containerFor(tabB);

      // Distinct project state.
      const projectA = NetcruxProject(
        version: 1,
        sourceFiles: <String>['/a.v'],
        topModule: 'a',
        defines: <String, String>{},
        includePaths: <String>[],
        extraYosysCommands: <String>[],
        lowerToStructural: false,
      );
      containerA.read(currentProjectProvider.notifier).setProject(projectA);
      expect(containerA.read(currentProjectProvider), projectA);
      expect(containerB.read(currentProjectProvider), NetcruxProject.empty);

      // Distinct selection state.
      const fakeElement = SelectedElement.cell(cellId: 'u_x');
      containerA.read(selectedElementProvider.notifier).select(fakeElement);
      expect(containerA.read(selectedElementProvider), isNot(Selection.empty));
      expect(containerB.read(selectedElementProvider), Selection.empty);

      // Distinct trace overlay state.
      const overlay = TraceOverlay(
        mode: TraceOverlayMode.fanin,
        highlightedCellIds: <String>{'u_x'},
        highlightedEdgeIds: <String>{},
        highlightedBoundaryPortIds: <String>{},
      );
      containerA.read(traceOverlayProvider.notifier).set(overlay);
      expect(containerA.read(traceOverlayProvider), overlay);
      expect(containerB.read(traceOverlayProvider), TraceOverlay.empty);

      // Distinct CDC analysis state. Root-hoisted before the design-seed
      // work — the scope-leak class: one shared result/filter set across
      // every tab.
      containerA.read(cdcAnalysisStateProvider.notifier).setSeverityFilter(
        const <CdcSeverity>{CdcSeverity.critical},
      );
      expect(
        containerA.read(cdcAnalysisStateProvider).severityFilter,
        const <CdcSeverity>{CdcSeverity.critical},
      );
      expect(
        containerB.read(cdcAnalysisStateProvider).severityFilter,
        CdcAnalysisState.empty.severityFilter,
      );
      // The derived views must track their own tab's state, not root's.
      expect(
        containerA.read(cdcSeverityFilterProvider),
        const <CdcSeverity>{CdcSeverity.critical},
      );
      expect(
        containerB.read(cdcSeverityFilterProvider),
        CdcAnalysisState.empty.severityFilter,
      );

      // Distinct RTL source-pane state. Root-hoisted before the per-tab
      // source-pane fix — the same scope-leak class: one shared pane
      // content / highlighted-lines / scroll state across every tab, and
      // its internal `sourcePaneServiceProvider` read resolved ROOT's
      // service instead of the active tab's.
      containerA.read(sourcePaneStateProvider.notifier).setHighlightedLines(
        const <int>{7, 8},
      );
      expect(
        containerA.read(sourcePaneStateProvider).highlightedLines,
        const <int>{7, 8},
      );
      expect(
        containerB.read(sourcePaneStateProvider).highlightedLines,
        isEmpty,
      );
    });

    test('per-tab overrides do not bleed into the root container', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final manager = TabContainerManager(
        rootContainer: root,
        overridesFactory: netcruxTabOverridesFactory,
      );
      addTearDown(manager.dispose);
      final container = manager.containerFor(TabId.generate());

      container.read(hierarchyTreeProvider.notifier).setFilterText('search');
      expect(container.read(hierarchyTreeProvider).filterText, 'search');
      // Root container's hierarchy state is unaffected.
      expect(root.read(hierarchyTreeProvider).filterText, isEmpty);
    });
  });

  group('netcruxPaneOverridesFactory', () {
    test(
      'two per-pane containers publish independent render-stats streams',
      () {
        final root = ProviderContainer();
        addTearDown(root.dispose);
        final manager = PaneContainerManager(
          rootContainer: root,
          overridesFactory: netcruxPaneOverridesFactory,
        );
        addTearDown(manager.dispose);
        final paneA = manager.containerFor(PaneId.generate());
        final paneB = manager.containerFor(PaneId.generate());

        const statsA = PaneRenderStats(
          frameNumber: 7,
          paintMicroseconds: 1234,
          visibleCells: 10,
          visibleEdges: 20,
          totalCells: 10,
          totalEdges: 20,
        );
        paneA.read(paneRenderStatsProvider.notifier).record(statsA);
        expect(paneA.read(paneRenderStatsProvider), statsA);
        expect(paneB.read(paneRenderStatsProvider), PaneRenderStats.empty);
      },
    );
  });

  group('viewportTransformProvider', () {
    test('per-tab viewport state is independent', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final manager = TabContainerManager(
        rootContainer: root,
        overridesFactory: netcruxTabOverridesFactory,
      );
      addTearDown(manager.dispose);
      final a = manager.containerFor(TabId.generate());
      final b = manager.containerFor(TabId.generate());
      a.read(viewportTransformProvider.notifier).setZoom(2.5);
      expect(a.read(viewportTransformProvider).zoom, 2.5);
      expect(b.read(viewportTransformProvider).zoom, 1.0);
    });
  });
}
