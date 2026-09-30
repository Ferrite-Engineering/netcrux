// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/waveform_source_service.dart';
import 'package:netcrux/services/waveform/waveform_source_service_provider.dart';

void main() {
  group('waveformSourceServiceProvider', () {
    test('default resolves to NoopWaveformSourceService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(waveformSourceServiceProvider);
      expect(service, isA<NoopWaveformSourceService>());
    });
  });
}
