// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';

void main() {
  group('NoopXTraceService', () {
    const service = NoopXTraceService();

    test('returns empty result for any input', () {
      final result = service.trace(
        const XTraceRequest(
          laidOut: LaidOutGraph.empty,
          selection: SelectedElement.none(),
        ),
      );
      expect(result, XTraceResult.empty);
    });

    test('returns empty result even with a wire selection', () {
      final result = service.trace(
        const XTraceRequest(
          laidOut: LaidOutGraph.empty,
          selection: SelectedElement.wire(edgeId: 'e_4', netId: 4),
          simulationTime: 100,
          maxDepth: 5,
        ),
      );
      expect(result, XTraceResult.empty);
    });
  });

  group('XTraceRequest', () {
    test('exposes the supplied fields verbatim', () {
      const req = XTraceRequest(
        laidOut: LaidOutGraph.empty,
        selection: SelectedElement.wire(edgeId: 'e_1', netId: 1),
        simulationTime: 250,
        maxDepth: 8,
      );
      expect(req.simulationTime, 250);
      expect(req.maxDepth, 8);
      expect(req.selection, isA<SelectedElementWire>());
      expect(req.laidOut, LaidOutGraph.empty);
    });

    test('defaultMaxDepth applies when omitted', () {
      const req = XTraceRequest(
        laidOut: LaidOutGraph.empty,
        selection: SelectedElement.none(),
      );
      expect(req.maxDepth, XTraceRequest.defaultMaxDepth);
      expect(req.simulationTime, isNull);
    });
  });

  group('XTraceStep', () {
    test('equality + hash', () {
      const a = XTraceStep(
        depth: 1,
        netId: 5,
        edgeId: 'e_5',
        value: 'x',
        cellId: 'u_alu',
      );
      const b = XTraceStep(
        depth: 1,
        netId: 5,
        edgeId: 'e_5',
        value: 'x',
        cellId: 'u_alu',
      );
      const c = XTraceStep(
        depth: 2,
        netId: 5,
        edgeId: 'e_5',
        value: 'x',
        cellId: 'u_alu',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('isUnknown detects x in scalar and vector values', () {
      const xStep = XTraceStep(
        depth: 0,
        netId: 1,
        edgeId: 'e_1',
        value: 'x',
      );
      const vectorWithX = XTraceStep(
        depth: 0,
        netId: 1,
        edgeId: 'e_1',
        value: '10xx',
      );
      const knownStep = XTraceStep(
        depth: 0,
        netId: 1,
        edgeId: 'e_1',
        value: '1010',
      );
      const noValue = XTraceStep(depth: 0, netId: 1, edgeId: 'e_1');
      expect(xStep.isUnknown, isTrue);
      expect(vectorWithX.isUnknown, isTrue);
      expect(knownStep.isUnknown, isFalse);
      expect(noValue.isUnknown, isFalse);
    });
  });

  group('XTraceResult', () {
    test('empty constant is the noTraceableSelection sentinel', () {
      expect(XTraceResult.empty.chain, isEmpty);
      expect(
        XTraceResult.empty.termination,
        XTraceTermination.noTraceableSelection,
      );
      expect(XTraceResult.empty.rootNetId, isNull);
      expect(XTraceResult.empty.isEmpty, isTrue);
    });

    test('equality compares termination + chain', () {
      const a = XTraceResult(
        rootNetId: 4,
        chain: <XTraceStep>[
          XTraceStep(depth: 0, netId: 4, edgeId: 'e_4', value: 'x'),
        ],
        termination: XTraceTermination.foundOrigin,
      );
      const b = XTraceResult(
        rootNetId: 4,
        chain: <XTraceStep>[
          XTraceStep(depth: 0, netId: 4, edgeId: 'e_4', value: 'x'),
        ],
        termination: XTraceTermination.foundOrigin,
      );
      const c = XTraceResult(
        rootNetId: 4,
        chain: <XTraceStep>[
          XTraceStep(depth: 0, netId: 4, edgeId: 'e_4', value: 'x'),
        ],
        termination: XTraceTermination.maxDepthReached,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('equality compares the origin reason and port', () {
      XTraceResult origin(XTraceOriginReason? reason, String? port) =>
          XTraceResult(
            rootNetId: 4,
            chain: const <XTraceStep>[
              XTraceStep(depth: 0, netId: 4, edgeId: 'e_4'),
            ],
            termination: XTraceTermination.foundOrigin,
            originReason: reason,
            originPortId: port,
          );
      final a = origin(XTraceOriginReason.undrivenInput, 'u_mul:B');
      expect(a, origin(XTraceOriginReason.undrivenInput, 'u_mul:B'));
      expect(
        a.hashCode,
        origin(XTraceOriginReason.undrivenInput, 'u_mul:B').hashCode,
      );
      expect(a, isNot(origin(XTraceOriginReason.xTiedInput, 'u_mul:B')));
      expect(a, isNot(origin(XTraceOriginReason.undrivenInput, 'u_mul:A')));
      // Omitting both keeps the pre-reason shape.
      expect(origin(null, null).originReason, isNull);
      expect(XTraceResult.empty.originReason, isNull);
    });
  });
}
