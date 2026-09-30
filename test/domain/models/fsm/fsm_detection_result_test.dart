// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/fsm/fsm.dart';
import 'package:netcrux/domain/models/fsm/fsm_detection_result.dart';
import 'package:netcrux/domain/models/fsm/fsm_encoding_hint.dart';
import 'package:netcrux/domain/models/fsm/fsm_state.dart';
import 'package:netcrux/domain/models/fsm/fsm_transition.dart';

void main() {
  group('FsmDetectionResult', () {
    test('empty result is empty', () {
      expect(FsmDetectionResult.empty.isEmpty, true);
      expect(FsmDetectionResult.empty.detectedFsms, isEmpty);
      expect(FsmDetectionResult.empty.candidateRegisters, isEmpty);
      expect(FsmDetectionResult.empty.detectionDiagnostics, isEmpty);
    });

    test('round-trips through JSON', () {
      const fsm = Fsm(
        id: 'fsm-1',
        stateRegisterId: ElementId(
          kind: ElementKind.signal,
          path: 'top.dut.state_q',
        ),
        stateRegisterName: 'state_q',
        containingInstanceId: ElementId(
          kind: ElementKind.instance,
          path: 'top.dut',
        ),
        states: <FsmState>[
          FsmState(
            id: 's0',
            name: 'IDLE',
            value: '0x0',
            isReachable: true,
            isTerminal: false,
          ),
        ],
        transitions: <FsmTransition>[],
        encodingHint: FsmEncodingHint.binary,
      );
      const candidate = ElementId(
        kind: ElementKind.signal,
        path: 'top.dut.maybe_reg',
      );
      const result = FsmDetectionResult(
        detectedFsms: <Fsm>[fsm],
        candidateRegisters: <ElementId>[candidate],
        detectionDiagnostics: <String>['width 9 exceeds default upper bound'],
      );
      expect(FsmDetectionResult.fromJson(result.toJson()), result);
    });

    test('fsmById looks up by detected id', () {
      const fsm = Fsm(
        id: 'fsm-1',
        stateRegisterId: ElementId(kind: ElementKind.signal, path: 'a'),
        stateRegisterName: 'a',
        containingInstanceId: ElementId(kind: ElementKind.instance, path: 't'),
        states: <FsmState>[],
        transitions: <FsmTransition>[],
        encodingHint: FsmEncodingHint.unknown,
      );
      const result = FsmDetectionResult(
        detectedFsms: <Fsm>[fsm],
        candidateRegisters: <ElementId>[],
        detectionDiagnostics: <String>[],
      );
      expect(result.fsmById('fsm-1'), fsm);
      expect(result.fsmById('nope'), isNull);
    });

    test('equality covers every collection', () {
      const a = FsmDetectionResult(
        detectedFsms: <Fsm>[],
        candidateRegisters: <ElementId>[],
        detectionDiagnostics: <String>['hello'],
      );
      const b = FsmDetectionResult(
        detectedFsms: <Fsm>[],
        candidateRegisters: <ElementId>[],
        detectionDiagnostics: <String>['hello'],
      );
      const c = FsmDetectionResult(
        detectedFsms: <Fsm>[],
        candidateRegisters: <ElementId>[],
        detectionDiagnostics: <String>['world'],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
