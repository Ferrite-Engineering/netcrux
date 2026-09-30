// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/fsm/fsm.dart';
import 'package:netcrux/domain/models/fsm/fsm_encoding_hint.dart';
import 'package:netcrux/domain/models/fsm/fsm_state.dart';
import 'package:netcrux/domain/models/fsm/fsm_transition.dart';

void main() {
  group('Fsm', () {
    const regId = ElementId(kind: ElementKind.signal, path: 'top.dut.state_q');
    const instId = ElementId(kind: ElementKind.instance, path: 'top.dut');

    Fsm sampleFsm() {
      return const Fsm(
        id: 'fsm-1',
        stateRegisterId: regId,
        stateRegisterName: 'state_q',
        containingInstanceId: instId,
        states: <FsmState>[
          FsmState(
            id: 's0',
            name: 'IDLE',
            value: '0x00',
            isReachable: true,
            isTerminal: false,
          ),
          FsmState(
            id: 's1',
            name: 'RUN',
            value: '0x01',
            isReachable: true,
            isTerminal: false,
          ),
          FsmState(
            id: 's2',
            name: 'DEAD',
            value: '0x02',
            isReachable: false,
            isTerminal: true,
          ),
        ],
        transitions: <FsmTransition>[
          FsmTransition(
            fromStateId: 's0',
            toStateId: 's1',
            conditionExpression: 'start',
          ),
          FsmTransition(
            fromStateId: 's1',
            toStateId: 's0',
            conditionExpression: 'done',
          ),
        ],
        encodingHint: FsmEncodingHint.binary,
        resetStateId: 's0',
      );
    }

    test('round-trips through JSON preserving every field', () {
      final fsm = sampleFsm();
      expect(Fsm.fromJson(fsm.toJson()), fsm);
    });

    test('round-trips through JSON without resetStateId', () {
      final fsm = sampleFsm().copyWith(clearResetStateId: true);
      final restored = Fsm.fromJson(fsm.toJson());
      expect(restored.resetStateId, isNull);
      expect(restored, fsm);
    });

    test('stateById returns matching state or null', () {
      final fsm = sampleFsm();
      expect(fsm.stateById('s1')?.name, 'RUN');
      expect(fsm.stateById('nope'), isNull);
    });

    test('equality is value-based across all collections', () {
      final a = sampleFsm();
      final b = sampleFsm();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      final c = a.copyWith(encodingHint: FsmEncodingHint.oneHot);
      expect(a, isNot(c));
    });

    test('copyWith clearResetStateId removes the reset pointer', () {
      final fsm = sampleFsm();
      final cleared = fsm.copyWith(clearResetStateId: true);
      expect(cleared.resetStateId, isNull);
      expect(cleared.id, fsm.id);
    });

    test('fromJson with empty maps yields an empty FSM', () {
      final empty = Fsm.fromJson(const <String, Object?>{});
      expect(empty.id, '');
      expect(empty.states, isEmpty);
      expect(empty.transitions, isEmpty);
      expect(empty.encodingHint, FsmEncodingHint.unknown);
    });
  });
}
