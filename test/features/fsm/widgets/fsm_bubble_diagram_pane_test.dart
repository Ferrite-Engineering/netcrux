// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/fsm/fsm.dart';
import 'package:netcrux/domain/models/fsm/fsm_encoding_hint.dart';
import 'package:netcrux/domain/models/fsm/fsm_state.dart';
import 'package:netcrux/domain/models/fsm/fsm_transition.dart';
import 'package:netcrux/features/fsm/providers/selected_fsm_provider.dart';
import 'package:netcrux/features/fsm/widgets/fsm_bubble_diagram_pane.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const _regId = ElementId(kind: ElementKind.signal, path: 'top.dut.state_q');
const _instId = ElementId(kind: ElementKind.instance, path: 'top.dut');

const Fsm _fsmFixture = Fsm(
  id: 'fsm-1',
  stateRegisterId: _regId,
  stateRegisterName: 'state_q',
  containingInstanceId: _instId,
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
    FsmTransition(fromStateId: 's1', toStateId: 's0'),
  ],
  encodingHint: FsmEncodingHint.binary,
  resetStateId: 's0',
);

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('FsmBubbleDiagramPane', () {
    testWidgets('renders empty state when no FSM is focused', (tester) async {
      await tester.pumpWidget(_wrap(const FsmBubbleDiagramPane()));
      await tester.pumpAndSettle();
      // Title + hint render as one CruxPanelEmptyState message.
      expect(find.textContaining('No FSM selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders states and transitions when an FSM is focused', (
      tester,
    ) async {
      late ProviderContainer capturedContainer;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              capturedContainer = ProviderScope.containerOf(
                context,
                listen: false,
              );
              // ignore: prefer_const_constructors — MaterialApp args are non-const.
              return MaterialApp(
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: const Scaffold(body: FsmBubbleDiagramPane()),
              );
            },
          ),
        ),
      );
      capturedContainer
          .read(selectedFsmProvider.notifier)
          .focusFsm(_fsmFixture);
      await tester.pumpAndSettle();
      expect(find.text('IDLE'), findsOneWidget);
      expect(find.text('RUN'), findsOneWidget);
      expect(find.text('DEAD'), findsOneWidget);
      expect(find.text('RESET'), findsOneWidget);
      expect(find.text('UNREACHABLE'), findsOneWidget);
      expect(find.text('TERMINAL'), findsOneWidget);
      // Transition row renders both endpoint names.
      expect(find.textContaining('start'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('onSelectState fires when a state row is tapped', (
      tester,
    ) async {
      late ProviderContainer capturedContainer;
      FsmState? captured;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              capturedContainer = ProviderScope.containerOf(
                context,
                listen: false,
              );
              return MaterialApp(
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(
                  body: FsmBubbleDiagramPane(
                    onSelectState: (s) => captured = s,
                  ),
                ),
              );
            },
          ),
        ),
      );
      capturedContainer
          .read(selectedFsmProvider.notifier)
          .focusFsm(_fsmFixture);
      await tester.pumpAndSettle();
      await tester.tap(find.text('RUN'));
      await tester.pump();
      expect(captured?.id, 's1');
    });

    testWidgets('highlight footer renders the highlighted state name', (
      tester,
    ) async {
      late ProviderContainer capturedContainer;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              capturedContainer = ProviderScope.containerOf(
                context,
                listen: false,
              );
              // ignore: prefer_const_constructors — MaterialApp args are non-const.
              return MaterialApp(
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: const Scaffold(body: FsmBubbleDiagramPane()),
              );
            },
          ),
        ),
      );
      capturedContainer.read(selectedFsmProvider.notifier)
        ..focusFsm(_fsmFixture)
        ..highlightState('s1');
      await tester.pumpAndSettle();
      expect(find.textContaining('Highlighted: RUN'), findsOneWidget);
    });

    for (final locale in const <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exception in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: const Scaffold(body: FsmBubbleDiagramPane()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
