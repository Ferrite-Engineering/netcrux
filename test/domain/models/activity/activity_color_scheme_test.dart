// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/activity_color_scheme.dart';

int _r(Color c) => (c.toARGB32() >> 16) & 0xFF;
int _g(Color c) => (c.toARGB32() >> 8) & 0xFF;
int _b(Color c) => c.toARGB32() & 0xFF;

void main() {
  group('ActivityColorScheme', () {
    test('JSON round-trip preserves each variant', () {
      for (final s in ActivityColorScheme.values) {
        expect(ActivityColorScheme.fromJsonString(s.toJsonString()), s);
      }
      expect(
        ActivityColorScheme.fromJsonString('nonexistent'),
        ActivityColorScheme.heatmapRedBlue,
      );
    });

    test('heatmapRedBlue hits the expected control points', () {
      final cold = ActivityColorScheme.heatmapRedBlue.colorForScore(0);
      final mid = ActivityColorScheme.heatmapRedBlue.colorForScore(0.5);
      final hot = ActivityColorScheme.heatmapRedBlue.colorForScore(1);
      // Blue at 0.0 (#2D58D8).
      expect(_r(cold), 0x2D);
      expect(_g(cold), 0x58);
      expect(_b(cold), 0xD8);
      // Yellow at 0.5 (#F2C94C).
      expect(_r(mid), 0xF2);
      expect(_g(mid), 0xC9);
      expect(_b(mid), 0x4C);
      // Red at 1.0 (#E74C3C).
      expect(_r(hot), 0xE7);
      expect(_g(hot), 0x4C);
      expect(_b(hot), 0x3C);
    });

    test('heatmapViridis hits the expected control points', () {
      final cold = ActivityColorScheme.heatmapViridis.colorForScore(0);
      final mid = ActivityColorScheme.heatmapViridis.colorForScore(0.5);
      final hot = ActivityColorScheme.heatmapViridis.colorForScore(1);
      // Dark purple (#440154).
      expect(_r(cold), 0x44);
      expect(_g(cold), 0x01);
      expect(_b(cold), 0x54);
      // Green (#1FA187).
      expect(_r(mid), 0x1F);
      expect(_g(mid), 0xA1);
      expect(_b(mid), 0x87);
      // Bright yellow (#FDE725).
      expect(_r(hot), 0xFD);
      expect(_g(hot), 0xE7);
      expect(_b(hot), 0x25);
    });

    test('heatmapGrayscale interpolates between light and dark', () {
      final cold = ActivityColorScheme.heatmapGrayscale.colorForScore(0);
      final hot = ActivityColorScheme.heatmapGrayscale.colorForScore(1);
      expect(_r(cold), 0xE0);
      expect(_r(hot), 0x1C);
    });

    test('out-of-range scores clamp to [0, 1]', () {
      final under = ActivityColorScheme.heatmapRedBlue.colorForScore(-0.5);
      final over = ActivityColorScheme.heatmapRedBlue.colorForScore(1.5);
      expect(under, ActivityColorScheme.heatmapRedBlue.colorForScore(0));
      expect(over, ActivityColorScheme.heatmapRedBlue.colorForScore(1));
    });

    test('interpolation is deterministic (same input → same output)', () {
      final a = ActivityColorScheme.heatmapViridis.colorForScore(0.37);
      final b = ActivityColorScheme.heatmapViridis.colorForScore(0.37);
      expect(a, b);
    });
  });
}
