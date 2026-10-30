// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/elaboration_time_limit.dart';
import 'package:netcrux/domain/interfaces/elaboration_timeout_policy.dart';
import 'package:netcrux/services/yosys/elaboration_timeout_provider.dart';

ElaborationSizeEstimate _bytes(int bytes) =>
    ElaborationSizeEstimate(sourceFileCount: 1, totalSourceBytes: bytes);

const int _mb = 1024 * 1024;

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
      expect(
        policy.timeoutFor(_bytes(4 * 1024)),
        DefaultElaborationTimeoutPolicy.floor,
      );
    });

    test('scales linearly with source size between floor and ceiling', () {
      // 64 MB at 256 KB/s = 256 s.
      final budget = policy.timeoutFor(_bytes(64 * _mb));
      expect(budget, const Duration(seconds: 256));
      expect(budget, greaterThan(DefaultElaborationTimeoutPolicy.floor));
      expect(budget, lessThan(DefaultElaborationTimeoutPolicy.ceiling));
      expect(
        policy.timeoutFor(_bytes(128 * _mb)),
        budget * 2,
        reason: 'twice the source, twice the budget',
      );
    });

    test('is not cut off at ten minutes', () {
      // 300 MB of source used to reach the old ten-minute cap.
      expect(
        policy.timeoutFor(_bytes(300 * _mb)),
        greaterThan(const Duration(minutes: 10)),
      );
    });

    test(
      'gives a five-million-gate source several times what Yosys needed',
      () {
        // The 660 MB structural netlist of five million gates took Yosys 403 s
        // on a fast desktop. A machine four times slower must still finish.
        final budget = policy.timeoutFor(_bytes(660 * _mb));
        expect(budget, greaterThan(const Duration(seconds: 403 * 6)));
        expect(budget, const Duration(minutes: 44));
      },
    );

    test('a source beyond the ceiling gets the ceiling', () {
      expect(
        policy.timeoutFor(_bytes(50 * 1024 * _mb)),
        DefaultElaborationTimeoutPolicy.ceiling,
      );
    });

    test('never returns a zero or negative budget', () {
      for (final limit in ElaborationTimeLimit.values) {
        final budget = DefaultElaborationTimeoutPolicy(
          limit: limit,
        ).timeoutFor(ElaborationSizeEstimate.empty);
        expect(budget, greaterThan(Duration.zero), reason: limit.name);
      }
    });

    test('extended allows four times the automatic budget', () {
      const extended = DefaultElaborationTimeoutPolicy(
        limit: ElaborationTimeLimit.extended,
      );
      expect(extended.killOnTimeout, isTrue);
      expect(
        extended.timeoutFor(_bytes(64 * _mb)),
        policy.timeoutFor(_bytes(64 * _mb)) * 4,
      );
      expect(
        extended.timeoutFor(ElaborationSizeEstimate.empty),
        DefaultElaborationTimeoutPolicy.floor * 4,
      );
      // Past the ceiling the multiple still applies.
      expect(
        extended.timeoutFor(_bytes(50 * 1024 * _mb)),
        DefaultElaborationTimeoutPolicy.ceiling * 4,
      );
    });

    test('none does not stop Yosys on a timer', () {
      const none = DefaultElaborationTimeoutPolicy(
        limit: ElaborationTimeLimit.none,
      );
      expect(none.killOnTimeout, isFalse);
    });
  });
}
