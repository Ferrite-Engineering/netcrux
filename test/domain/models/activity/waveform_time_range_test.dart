// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/waveform_time_range.dart';

void main() {
  group('WaveformTimeRange', () {
    test('JSON round-trip preserves all fields', () {
      const range = WaveformTimeRange(
        startNs: 100,
        endNs: 500,
        label: 'custom',
      );
      expect(WaveformTimeRange.fromJson(range.toJson()), range);
    });

    test('isFullSimulationSentinel only for the 0..0 instance', () {
      expect(
        WaveformTimeRange.fullSimulationSentinel.isFullSimulationSentinel,
        true,
      );
      expect(
        const WaveformTimeRange(
          startNs: 0,
          endNs: 1,
          label: 'tiny',
        ).isFullSimulationSentinel,
        false,
      );
    });

    test('expandedAgainst replaces only the sentinel', () {
      final expanded = WaveformTimeRange.fullSimulationSentinel.expandedAgainst(
        1000,
        fullLabel: 'Full simulation',
      );
      expect(expanded.startNs, 0);
      expect(expanded.endNs, 1000);
      expect(expanded.label, 'Full simulation');

      const concrete = WaveformTimeRange(
        startNs: 100,
        endNs: 200,
        label: 'custom',
      );
      expect(concrete.expandedAgainst(5000), concrete);
    });

    test('expandedAgainst clamps negative source end times to 0', () {
      final expanded = WaveformTimeRange.fullSimulationSentinel.expandedAgainst(
        -50,
      );
      expect(expanded.startNs, 0);
      expect(expanded.endNs, 0);
    });

    test('firstPercent / lastPercent / middlePercent compute windows', () {
      expect(
        WaveformTimeRange.firstPercent(1000),
        const WaveformTimeRange(startNs: 0, endNs: 100, label: 'first'),
      );
      expect(
        WaveformTimeRange.lastPercent(1000),
        const WaveformTimeRange(startNs: 900, endNs: 1000, label: 'last'),
      );
      expect(
        WaveformTimeRange.middlePercent(1000),
        const WaveformTimeRange(startNs: 450, endNs: 550, label: 'middle'),
      );
      // Custom percent.
      expect(
        WaveformTimeRange.firstPercent(1000, percent: 25, label: 'q1'),
        const WaveformTimeRange(startNs: 0, endNs: 250, label: 'q1'),
      );
    });

    test('widthNs returns 0 for the sentinel and the difference otherwise', () {
      expect(WaveformTimeRange.fullSimulationSentinel.widthNs, 0);
      expect(
        const WaveformTimeRange(startNs: 100, endNs: 250, label: 'x').widthNs,
        150,
      );
    });

    test('equality and hash are value-based', () {
      const a = WaveformTimeRange(startNs: 0, endNs: 100, label: 'a');
      const b = WaveformTimeRange(startNs: 0, endNs: 100, label: 'a');
      const c = WaveformTimeRange(startNs: 0, endNs: 100, label: 'b');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, false);
    });
  });
}
