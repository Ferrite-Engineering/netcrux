// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/services/schematic/x_trace_service_provider.dart';

class _FakeXTraceService implements XTraceService {
  const _FakeXTraceService(this.label);
  final String label;

  @override
  Future<XTraceResult> traceAsync(XTraceRequest request) async =>
      trace(request);

  @override
  XTraceResult trace(XTraceRequest request) {
    return XTraceResult(
      rootNetId: 99,
      chain: <XTraceStep>[
        XTraceStep(
          depth: 0,
          netId: 99,
          edgeId: 'fake:$label',
          value: 'x',
        ),
      ],
      termination: XTraceTermination.foundOrigin,
    );
  }
}

void main() {
  group('xTraceServiceProvider', () {
    test('open-core default returns a NoopXTraceService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(xTraceServiceProvider);
      expect(service, isA<NoopXTraceService>());

      final result = service.trace(
        const XTraceRequest(
          laidOut: LaidOutGraph.empty,
          selection: SelectedElement.wire(edgeId: 'e_1', netId: 1),
        ),
      );
      expect(result, XTraceResult.empty);
    });

    test('override replaces the default service (Pro overlay pattern)', () {
      const fake = _FakeXTraceService('pro');
      final container = ProviderContainer(
        overrides: [
          xTraceServiceProvider.overrideWith((_) => fake),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(xTraceServiceProvider);
      expect(identical(service, fake), isTrue);

      final result = service.trace(
        const XTraceRequest(
          laidOut: LaidOutGraph.empty,
          selection: SelectedElement.wire(edgeId: 'e_x', netId: 99),
          simulationTime: 100,
          maxDepth: 5,
        ),
      );
      expect(result.rootNetId, 99);
      expect(result.chain, hasLength(1));
      expect(result.chain.first.edgeId, 'fake:pro');
      expect(result.termination, XTraceTermination.foundOrigin);
    });
  });
}
