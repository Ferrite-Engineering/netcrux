// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';

void main() {
  group('NoopConeOfInfluenceService', () {
    const service = NoopConeOfInfluenceService();

    test('returns empty overlay for any input', () {
      final overlay = service.compute(
        const ConeOfInfluenceRequest(
          laidOut: LaidOutGraph.empty,
          selection: SelectedElement.none(),
          mode: ConeOfInfluenceMode.fanin,
          depth: 5,
        ),
      );
      expect(overlay, TraceOverlay.empty);
    });

    test('returns empty overlay even with cell selection', () {
      final overlay = service.compute(
        const ConeOfInfluenceRequest(
          laidOut: LaidOutGraph.empty,
          selection: SelectedElement.cell(cellId: 'u_alu'),
          mode: ConeOfInfluenceMode.fanout,
          depth: null,
        ),
      );
      expect(overlay, TraceOverlay.empty);
    });
  });

  group('ConeOfInfluenceRequest', () {
    test('exposes the supplied fields verbatim', () {
      const req = ConeOfInfluenceRequest(
        laidOut: LaidOutGraph.empty,
        selection: SelectedElement.cell(cellId: 'u_dff'),
        mode: ConeOfInfluenceMode.fanin,
        depth: 3,
      );
      expect(req.mode, ConeOfInfluenceMode.fanin);
      expect(req.depth, 3);
      expect(req.selection, isA<SelectedElementCell>());
      expect(req.laidOut, LaidOutGraph.empty);
    });
  });
}
