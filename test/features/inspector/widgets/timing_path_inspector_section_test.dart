// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/inspector/providers/received_timing_path_provider.dart';
import 'package:netcrux/features/inspector/widgets/inspector_panel.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const ReceivedTimingPath _path = ReceivedTimingPath(
  peer: 'SimCrux',
  fidelity: TimingPathFidelity.statement,
  registers: <TimingPathRegister>[
    TimingPathRegister(
      name: 'top.u_div.cnt_q[3]',
      place: TimingPathRegisterPlace.shown,
    ),
    TimingPathRegister(
      name: 'top.u_ctl.state',
      place: TimingPathRegisterPlace.otherScope,
    ),
    TimingPathRegister(
      name: 'top.u_div.cnt_q[23]',
      place: TimingPathRegisterPlace.notFound,
    ),
  ],
  statements: <String>['div.v:21'],
);

Widget _wrap(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: const Scaffold(
      body: SizedBox(width: 360, height: 600, child: InspectorPanel()),
    ),
  ),
);

void main() {
  testWidgets('no path: the Inspector is as before', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('timingPathInspectorSection')),
      findsNothing,
    );
    expect(find.text('No selection'), findsOneWidget);
  });

  testWidgets(
    'a received path reads with no selection, its mapping as sent',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(receivedTimingPathProvider.notifier).show(_path);
      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();
      expect(find.text('Timing path from SimCrux'), findsOneWidget);
      // The chip and the Mapping row both say "statement", never stronger.
      expect(find.text('statement'), findsNWidgets(2));
      expect(find.text('nearest register'), findsNothing);
      expect(find.text('top.u_div.cnt_q[3]'), findsOneWidget);
      expect(find.text('top.u_ctl.state (in another scope)'), findsOneWidget);
      expect(
        find.text('top.u_div.cnt_q[23] (not in this design)'),
        findsOneWidget,
      );
      expect(find.text('div.v:21'), findsOneWidget);
      // The selection's own sections are still there below it.
      expect(find.text('No selection'), findsOneWidget);
    },
  );

  testWidgets('it is announced, and its words name the peer and mapping', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(receivedTimingPathProvider.notifier).show(_path);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        RegExp('Timing path from SimCrux, mapping: statement'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('Dismiss clears it', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(receivedTimingPathProvider.notifier).show(_path);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timingPathDismiss')));
    await tester.pumpAndSettle();
    expect(container.read(receivedTimingPathProvider), isNull);
    expect(find.text('Timing path from SimCrux'), findsNothing);
  });

  for (final locale in const <Locale>[
    Locale('zh', 'CN'),
    Locale('zh'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    testWidgets('pumps cleanly in ${locale.toLanguageTag()}', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(receivedTimingPathProvider.notifier).show(_path);
      await tester.pumpWidget(_wrap(container, locale: locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('div.v:21'), findsOneWidget);
    });
  }

  test('TimingPathFidelity never reads a mapping stronger than sent', () {
    expect(TimingPathFidelity.parse('register'), TimingPathFidelity.register);
    expect(TimingPathFidelity.parse('span'), TimingPathFidelity.span);
    expect(TimingPathFidelity.parse('REGISTER'), TimingPathFidelity.unmapped);
    expect(TimingPathFidelity.parse(1), TimingPathFidelity.unmapped);
    expect(TimingPathFidelity.parse(null), TimingPathFidelity.unmapped);
  });
}
