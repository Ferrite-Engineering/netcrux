// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/activity_analysis_service.dart';
import 'package:netcrux/services/activity/activity_analysis_service_provider.dart';

void main() {
  group('activityAnalysisServiceProvider', () {
    test('default resolves to NoopActivityAnalysisService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(activityAnalysisServiceProvider);
      expect(service, isA<NoopActivityAnalysisService>());
    });
  });
}
