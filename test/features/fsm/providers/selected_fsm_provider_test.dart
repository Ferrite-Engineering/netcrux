// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/fsm/fsm.dart';
import 'package:netcrux/domain/models/fsm/fsm_encoding_hint.dart';
import 'package:netcrux/domain/models/fsm/fsm_state.dart';
import 'package:netcrux/domain/models/fsm/fsm_transition.dart';
import 'package:netcrux/features/fsm/providers/selected_fsm_provider.dart';

const _regId = ElementId(kind: ElementKind.signal, path: 'top.dut.state_q');
const _instId = ElementId(kind: ElementKind.instance, path: 'top.dut');

const Fsm _twoStateFsm = Fsm(
  id: 'fsm-1',
  stateRegisterId: _regId,
  stateRegisterName: 'state_q',
  containingInstanceId: _instId,
  states: <FsmState>[
    FsmState(
      id: 's0',
      name: 'IDLE',
      value: '0x0',
      isReachable: true,
      isTerminal: false,
    ),
    FsmState(
      id: 's1',
      name: 'RUN',
      value: '0x1',
      isReachable: true,
      isTerminal: false,
    ),
  ],
  transitions: <FsmTransition>[
    FsmTransition(fromStateId: 's0', toStateId: 's1'),
  ],
  encodingHint: FsmEncodingHint.binary,
  resetStateId: 's0',
);

void main() {
  group('SelectedFsmState', () {
    test('empty default has no FSM and no highlight', () {
      const state = SelectedFsmState.empty;
      expect(state.hasFsm, false);
      expect(state.selectedState, isNull);
      expect(state.bubblePositions, isEmpty);
    });

    test('selectedState resolves through the focused FSM', () {
      const state = SelectedFsmState(
        fsm: _twoStateFsm,
        selectedStateId: 's1',
      );
      expect(state.selectedState?.name, 'RUN');
    });

    test('selectedState is null when the FSM is null', () {
      const state = SelectedFsmState(selectedStateId: 's0');
      expect(state.selectedState, isNull);
    });

    test('selectedState is null when the id no longer exists', () {
      const state = SelectedFsmState(
        fsm: _twoStateFsm,
        selectedStateId: 'gone',
      );
      expect(state.selectedState, isNull);
    });

    test('equality includes the bubble positions map', () {
      const a = SelectedFsmState(
        fsm: _twoStateFsm,
        bubblePositions: <String, Offset>{'s0': Offset(10, 20)},
      );
      const b = SelectedFsmState(
        fsm: _twoStateFsm,
        bubblePositions: <String, Offset>{'s0': Offset(10, 20)},
      );
      const c = SelectedFsmState(
        fsm: _twoStateFsm,
        bubblePositions: <String, Offset>{'s0': Offset(99, 20)},
      );
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('SelectedFsmNotifier', () {
    test('focusFsm sets the FSM and clears highlight + positions', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFsmProvider.notifier)
        ..focusFsm(_twoStateFsm);
      addTearDown(notifier.clear);
      final state = container.read(selectedFsmProvider);
      expect(state.fsm, _twoStateFsm);
      expect(state.selectedStateId, isNull);
      expect(state.bubblePositions, isEmpty);
    });

    test('highlightState only accepts valid state ids', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedFsmProvider.notifier)
        ..focusFsm(_twoStateFsm)
        ..highlightState('s1');
      expect(container.read(selectedFsmProvider).selectedStateId, 's1');
      container.read(selectedFsmProvider.notifier).highlightState('invalid');
      expect(container.read(selectedFsmProvider).selectedStateId, 's1');
      container.read(selectedFsmProvider.notifier).highlightState(null);
      expect(container.read(selectedFsmProvider).selectedStateId, isNull);
    });

    test('setBubblePosition records per-state offsets', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedFsmProvider.notifier)
        ..focusFsm(_twoStateFsm)
        ..setBubblePosition('s0', const Offset(100, 200));
      expect(
        container.read(selectedFsmProvider).bubblePositions['s0'],
        const Offset(100, 200),
      );
      container
          .read(selectedFsmProvider.notifier)
          .setBubblePosition('gone', Offset.zero);
      expect(
        container.read(selectedFsmProvider).bubblePositions.containsKey('gone'),
        false,
      );
    });

    test('updateFsm preserves valid positions and clears stale highlight', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedFsmProvider.notifier)
        ..focusFsm(_twoStateFsm)
        ..setBubblePosition('s0', const Offset(10, 10))
        ..setBubblePosition('s1', const Offset(20, 20))
        ..highlightState('s1');
      const reducedFsm = Fsm(
        id: 'fsm-1',
        stateRegisterId: _regId,
        stateRegisterName: 'state_q',
        containingInstanceId: _instId,
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
      container.read(selectedFsmProvider.notifier).updateFsm(reducedFsm);
      final state = container.read(selectedFsmProvider);
      expect(state.bubblePositions.keys, <String>['s0']);
      expect(state.selectedStateId, isNull);
    });

    test('clear resets to the empty state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedFsmProvider.notifier)
        ..focusFsm(_twoStateFsm)
        ..highlightState('s0')
        ..clear();
      expect(container.read(selectedFsmProvider), SelectedFsmState.empty);
    });
  });

  group('Convenience providers', () {
    test('activeFsmProvider reflects the focused FSM', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeFsmProvider), isNull);
      container.read(selectedFsmProvider.notifier).focusFsm(_twoStateFsm);
      expect(container.read(activeFsmProvider), _twoStateFsm);
    });

    test('selectedFsmStateProvider reflects the highlight', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedFsmProvider.notifier)
        ..focusFsm(_twoStateFsm)
        ..highlightState('s1');
      expect(container.read(selectedFsmStateProvider)?.name, 'RUN');
    });
  });
}
