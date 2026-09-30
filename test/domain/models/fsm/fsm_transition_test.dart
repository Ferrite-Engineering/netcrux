// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/fsm/fsm_transition.dart';

void main() {
  group('FsmTransition', () {
    test('round-trips through JSON with all optional fields', () {
      const t = FsmTransition(
        fromStateId: 's0',
        toStateId: 's1',
        conditionExpression: 'req && !busy',
        priorityRank: 0,
      );
      expect(FsmTransition.fromJson(t.toJson()), t);
    });

    test('round-trips through JSON with no optional fields', () {
      const t = FsmTransition(fromStateId: 's0', toStateId: 's2');
      final restored = FsmTransition.fromJson(t.toJson());
      expect(restored.fromStateId, 's0');
      expect(restored.toStateId, 's2');
      expect(restored.conditionExpression, isNull);
      expect(restored.priorityRank, isNull);
    });

    test('isSelfLoop is true exactly when from == to', () {
      const self = FsmTransition(fromStateId: 's0', toStateId: 's0');
      const cross = FsmTransition(fromStateId: 's0', toStateId: 's1');
      expect(self.isSelfLoop, true);
      expect(cross.isSelfLoop, false);
    });

    test('equality is value-based across all fields', () {
      const a = FsmTransition(
        fromStateId: 's0',
        toStateId: 's1',
        conditionExpression: 'req',
        priorityRank: 1,
      );
      const b = FsmTransition(
        fromStateId: 's0',
        toStateId: 's1',
        conditionExpression: 'req',
        priorityRank: 1,
      );
      const c = FsmTransition(
        fromStateId: 's0',
        toStateId: 's1',
        conditionExpression: 'ack',
        priorityRank: 1,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith with clear flags resets optional fields', () {
      const t = FsmTransition(
        fromStateId: 's0',
        toStateId: 's1',
        conditionExpression: 'req',
        priorityRank: 2,
      );
      final cleared = t.copyWith(
        clearConditionExpression: true,
        clearPriorityRank: true,
      );
      expect(cleared.conditionExpression, isNull);
      expect(cleared.priorityRank, isNull);
      expect(cleared.fromStateId, 's0');
    });
  });
}
