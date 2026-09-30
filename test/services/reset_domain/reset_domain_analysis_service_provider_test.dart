// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/reset_domain_analysis_service.dart';
import 'package:netcrux/services/reset_domain/reset_domain_analysis_service_provider.dart';

class _FakeResetDomainAnalysisService extends NoopResetDomainAnalysisService {
  const _FakeResetDomainAnalysisService();
}

void main() {
  group('resetDomainAnalysisServiceProvider', () {
    test('open-core default is NoopResetDomainAnalysisService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(resetDomainAnalysisServiceProvider);
      expect(service, isA<NoopResetDomainAnalysisService>());
    });

    test('Pro-style override replaces the open-core default', () {
      final container = ProviderContainer(
        overrides: [
          resetDomainAnalysisServiceProvider.overrideWithValue(
            const _FakeResetDomainAnalysisService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final service = container.read(resetDomainAnalysisServiceProvider);
      expect(service, isA<_FakeResetDomainAnalysisService>());
    });
  });
}
