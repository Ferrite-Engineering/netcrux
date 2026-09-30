// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/elaboration_timeout_policy.dart';
import 'package:netcrux/services/yosys/elaboration_timeout_provider.dart';

void main() {
  group('DefaultElaborationTimeoutPolicy', () {
    const policy = DefaultElaborationTimeoutPolicy();

    test('killOnTimeout is true (the gap-closing default)', () {
      expect(policy.killOnTimeout, isTrue);
    });

    test('returns the floor for a tiny / empty design', () {
      expect(
        policy.timeoutFor(ElaborationSizeEstimate.empty),
        DefaultElaborationTimeoutPolicy.floor,
      );
      // A few-KB testbench is still under the floor.
      expect(
        policy.timeoutFor(
          const ElaborationSizeEstimate(
            sourceFileCount: 1,
            totalSourceBytes: 4 * 1024,
          ),
        ),
        DefaultElaborationTimeoutPolicy.floor,
      );
    });

    test('scales linearly with source size between floor and cap', () {
      // 64 MB at 512 KB/s = 128 s — comfortably between the 30 s floor
      // and the 10 min cap.
      final budget = policy.timeoutFor(
        const ElaborationSizeEstimate(
          sourceFileCount: 12,
          totalSourceBytes: 64 * 1024 * 1024,
        ),
      );
      expect(budget, const Duration(seconds: 128));
      expect(budget, greaterThan(DefaultElaborationTimeoutPolicy.floor));
      expect(budget, lessThan(DefaultElaborationTimeoutPolicy.cap));
    });

    test('caps an enormous design at 10 minutes', () {
      // 1 GB would scale to ~34 min; the cap clamps it.
      expect(
        policy.timeoutFor(
          const ElaborationSizeEstimate(
            sourceFileCount: 200,
            totalSourceBytes: 1024 * 1024 * 1024,
          ),
        ),
        DefaultElaborationTimeoutPolicy.cap,
      );
    });

    test('never returns a zero or negative budget', () {
      final budget = policy.timeoutFor(ElaborationSizeEstimate.empty);
      expect(budget, greaterThan(Duration.zero));
    });
  });
}
