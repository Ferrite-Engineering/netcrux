// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/collaboration/collab_presence_publisher.dart';

void main() {
  group('collabScopeSegments', () {
    test('is the inverse of collabScopePath, the top included', () {
      for (final path in const [
        <String>[],
        ['u_cpu'],
        ['u_cpu', 'u_alu'],
      ]) {
        final node = HierarchyNode(path: path, moduleName: 'm');
        expect(collabScopeSegments(collabScopePath(node)), path);
      }
    });

    test('the top of the design is no segments, not one empty one', () {
      expect(collabScopeSegments(''), isEmpty);
    });
  });

  group('collabPresenterView', () {
    test('describes scope, camera and trace', () {
      final view = collabPresenterView(
        scope: const HierarchyNode(path: ['u_cpu'], moduleName: 'cpu'),
        center: const Offset(10, 20),
        zoom: 1.5,
        trace: const TraceOverlay(
          mode: TraceOverlayMode.fanin,
          highlightedCellIds: {'u_alu'},
          highlightedEdgeIds: {'e_1'},
          highlightedBoundaryPortIds: {'port:clk'},
        ),
      );
      expect(view.scopePath, 'u_cpu');
      expect(
        view.camera,
        const SchematicCollabCamera(centerX: 10, centerY: 20, zoom: 1.5),
      );
      expect(view.trace!.mode, 'fanin');
      expect(view.trace!.allIds, {'u_alu', 'e_1', 'port:clk'});
    });

    test('no canvas yet means no camera; no overlay means no trace', () {
      final view = collabPresenterView(
        scope: null,
        center: null,
        zoom: 1,
        trace: TraceOverlay.empty,
      );
      expect(view.scopePath, '');
      expect(view.camera, isNull);
      expect(view.trace, isNull);
      expect(view.analysisPanel, isNull);
    });

    test('names the front analysis panel by its kind', () {
      final view = collabPresenterView(
        scope: null,
        center: null,
        zoom: 1,
        trace: TraceOverlay.empty,
        analysisPanel: AnalysisPanelKind.resetDomain,
      );
      expect(view.analysisPanel, 'resetDomain');
    });
  });
}
