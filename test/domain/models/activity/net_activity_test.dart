// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/net_activity.dart';

void main() {
  group('NetActivity', () {
    test('JSON round-trip preserves all fields', () {
      const na = NetActivity(
        netPath: 'top.cpu.alu.sum',
        transitionCount: 12345,
        dutyCyclePercent: 42.5,
        activityScore: 0.78,
        netBitWidth: 32,
      );
      expect(NetActivity.fromJson(na.toJson()), na);
    });

    test('JSON fromJson uses safe defaults for missing fields', () {
      final na = NetActivity.fromJson(const <String, Object?>{});
      expect(na.netPath, '');
      expect(na.transitionCount, 0);
      expect(na.dutyCyclePercent, 0.0);
      expect(na.activityScore, 0.0);
      expect(na.netBitWidth, 1);
    });

    test('asserts: transitionCount must be non-negative', () {
      expect(
        () => NetActivity(
          netPath: 'x',
          transitionCount: -1,
          dutyCyclePercent: 0,
          activityScore: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('asserts: dutyCyclePercent in [0, 100]', () {
      expect(
        () => NetActivity(
          netPath: 'x',
          transitionCount: 0,
          dutyCyclePercent: -1,
          activityScore: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => NetActivity(
          netPath: 'x',
          transitionCount: 0,
          dutyCyclePercent: 101,
          activityScore: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('asserts: activityScore in [0.0, 1.0]', () {
      expect(
        () => NetActivity(
          netPath: 'x',
          transitionCount: 0,
          dutyCyclePercent: 0,
          activityScore: -0.01,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => NetActivity(
          netPath: 'x',
          transitionCount: 0,
          dutyCyclePercent: 0,
          activityScore: 1.01,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('equality + hash + copyWith', () {
      const a = NetActivity(
        netPath: 'top.q',
        transitionCount: 1,
        dutyCyclePercent: 50,
        activityScore: 0.5,
      );
      const b = NetActivity(
        netPath: 'top.q',
        transitionCount: 1,
        dutyCyclePercent: 50,
        activityScore: 0.5,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      final c = a.copyWith(activityScore: 0.9);
      expect(c.activityScore, 0.9);
      expect(c.netPath, a.netPath);
      expect(a == c, false);
    });
  });
}
