// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/fsm_detection_service.dart';
import 'package:netcrux/domain/models/fsm/fsm.dart';
import 'package:netcrux/domain/models/fsm/fsm_detection_options.dart';
import 'package:netcrux/domain/models/fsm/fsm_detection_result.dart';
import 'package:netcrux/services/fsm/fsm_detection_service_provider.dart';

void main() {
  group('fsmDetectionServiceProvider', () {
    test('default resolves to NoopFsmDetectionService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(fsmDetectionServiceProvider);
      expect(service, isA<NoopFsmDetectionService>());
    });

    test('overrideWithValue replaces the registered service', () {
      final fake = _FakeFsmDetectionService();
      final container = ProviderContainer(
        overrides: [
          fsmDetectionServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(fsmDetectionServiceProvider), same(fake));
    });
  });
}

class _FakeFsmDetectionService implements FsmDetectionService {
  @override
  Future<FsmDetectionResult> detect({
    ElementId? scopeFilter,
    FsmDetectionOptions? options,
  }) async => FsmDetectionResult.empty;

  @override
  Future<Fsm?> detectAt(ElementId stateRegisterId) async => null;

  @override
  Stream<void> get detectionInvalidated => const Stream<void>.empty();
}
