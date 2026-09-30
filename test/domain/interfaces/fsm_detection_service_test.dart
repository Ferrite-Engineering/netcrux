// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/fsm_detection_service.dart';
import 'package:netcrux/domain/models/fsm/fsm_detection_result.dart';

void main() {
  group('NoopFsmDetectionService', () {
    test('detect returns the empty result', () async {
      const service = NoopFsmDetectionService();
      final result = await service.detect();
      expect(result, FsmDetectionResult.empty);
    });

    test('detect with scope filter still returns empty', () async {
      const service = NoopFsmDetectionService();
      final result = await service.detect(
        scopeFilter: const ElementId(
          kind: ElementKind.scope,
          path: 'top.cpu',
        ),
      );
      expect(result, FsmDetectionResult.empty);
    });

    test('detectAt throws UnimplementedFsmDetection', () async {
      const service = NoopFsmDetectionService();
      expect(
        () => service.detectAt(
          const ElementId(kind: ElementKind.signal, path: 'top.reg'),
        ),
        throwsA(isA<UnimplementedFsmDetection>()),
      );
    });

    test('detectionInvalidated is an empty stream', () async {
      const service = NoopFsmDetectionService();
      expect(await service.detectionInvalidated.isEmpty, true);
    });
  });

  group('UnimplementedFsmDetection', () {
    test('toString includes the message when provided', () {
      const exception = UnimplementedFsmDetection('no overlay');
      expect(exception.toString(), contains('no overlay'));
    });

    test('toString omits the message when absent', () {
      const exception = UnimplementedFsmDetection();
      expect(exception.toString(), 'UnimplementedFsmDetection');
    });
  });
}
