// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/services/schematic/cone_of_influence_service_provider.dart';

class _FakeConeService implements ConeOfInfluenceService {
  const _FakeConeService(this.label);
  final String label;

  @override
  Future<TraceOverlay> computeAsync(ConeOfInfluenceRequest request) async =>
      compute(request);

  @override
  TraceOverlay compute(ConeOfInfluenceRequest request) {
    return TraceOverlay(
      mode: request.mode == ConeOfInfluenceMode.fanin
          ? TraceOverlayMode.fanin
          : TraceOverlayMode.fanout,
      highlightedCellIds: {'fake:$label'},
      highlightedEdgeIds: const <String>{},
      highlightedBoundaryPortIds: const <String>{},
    );
  }
}

void main() {
  group('coneOfInfluenceServiceProvider', () {
    test('open-core default returns a NoopConeOfInfluenceService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(coneOfInfluenceServiceProvider);
      expect(service, isA<NoopConeOfInfluenceService>());

      final overlay = service.compute(
        const ConeOfInfluenceRequest(
          laidOut: LaidOutGraph.empty,
          selection: SelectedElement.cell(cellId: 'x'),
          mode: ConeOfInfluenceMode.fanin,
          depth: null,
        ),
      );
      expect(overlay, TraceOverlay.empty);
    });

    test('override replaces the default service (Pro overlay pattern)', () {
      const fake = _FakeConeService('pro');
      final container = ProviderContainer(
        overrides: [
          coneOfInfluenceServiceProvider.overrideWith((_) => fake),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(coneOfInfluenceServiceProvider);
      expect(identical(service, fake), isTrue);

      final overlay = service.compute(
        const ConeOfInfluenceRequest(
          laidOut: LaidOutGraph.empty,
          selection: SelectedElement.cell(cellId: 'u_alu'),
          mode: ConeOfInfluenceMode.fanout,
          depth: 2,
        ),
      );
      expect(overlay.highlightedCellIds, contains('fake:pro'));
      expect(overlay.mode, TraceOverlayMode.fanout);
    });
  });
}
