// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/fsm/fsm_state.dart';

void main() {
  group('FsmState', () {
    test('round-trips through JSON', () {
      const state = FsmState(
        id: 's2',
        name: 'IDLE',
        value: '0x03',
        isReachable: true,
        isTerminal: false,
      );
      final round = FsmState.fromJson(state.toJson());
      expect(round, state);
    });

    test('equality and hashCode are value-based', () {
      const a = FsmState(
        id: 's0',
        name: 'RUN',
        value: '0x01',
        isReachable: true,
        isTerminal: false,
      );
      const b = FsmState(
        id: 's0',
        name: 'RUN',
        value: '0x01',
        isReachable: true,
        isTerminal: false,
      );
      const c = FsmState(
        id: 's0',
        name: 'RUN',
        value: '0x02',
        isReachable: true,
        isTerminal: false,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith replaces only the named fields', () {
      const state = FsmState(
        id: 's0',
        name: 'A',
        value: '0x00',
        isReachable: true,
        isTerminal: false,
      );
      expect(state.copyWith(name: 'B').name, 'B');
      expect(state.copyWith(name: 'B').id, 's0');
      expect(state.copyWith(isTerminal: true).isTerminal, true);
    });

    test('fromJson tolerates missing fields with sensible defaults', () {
      final restored = FsmState.fromJson(const <String, Object?>{'id': 's0'});
      expect(restored.id, 's0');
      expect(restored.name, '');
      expect(restored.value, '0x0');
      expect(restored.isReachable, true);
      expect(restored.isTerminal, false);
    });
  });
}
