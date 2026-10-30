// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: a scale regression test; it asserts how long the list
// takes to move, and the English text only because the generated messages
// are English.
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// A design whose Yosys run printed tens of thousands of warnings once froze
/// the window: the Diagnostics list placed a row by building and laying out
/// every row before it, so moving to a row deep in the list took time in
/// proportion to its number (measured with this test's harness: 2 s at 2,000
/// rows, 15 s at 8,000, 79 s at 16,000), on the UI thread. These tests move
/// around a list of that size and bound how long each step takes.
///
/// The bound is deliberately loose: many times what the fixed list needs
/// (tens of milliseconds) and well under what the broken one took at this
/// size, so it notices the list becoming a function of its length again
/// without being a timing test of the machine.
void main() {
  const warnings = 8000;
  const infos = 8000;
  const budget = Duration(seconds: 5);

  String stderrText() {
    final b = StringBuffer();
    for (var i = 0; i < warnings; i++) {
      b.writeln('Warning: Wire top.u$i.w$i is used but has no driver.');
    }
    for (var i = 0; i < infos; i++) {
      b.writeln('Info: top.v:$i: net n$i has no loads.');
    }
    return b.toString();
  }

  Future<ProviderContainer> pumpDrawer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(
              localizationsDelegates: [
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SizedBox(height: 400, child: TabDiagnosticsDrawer()),
              ),
            );
          },
        ),
      ),
    );
    return container;
  }

  /// How long [step] and the frame it causes take.
  Future<Duration> timed(
    WidgetTester tester,
    String name,
    void Function() step,
  ) async {
    final clock = Stopwatch()..start();
    step();
    await tester.pump();
    clock.stop();
    debugPrint('diagnostics list, $name: ${clock.elapsedMilliseconds} ms');
    return clock.elapsed;
  }

  testWidgets(
    'a very long list can be scrolled anywhere, filtered and cleared quickly',
    timeout: const Timeout(Duration(minutes: 4)),
    (tester) async {
      final container = await pumpDrawer(tester);
      final stderr = container.read(elaborationStderrProvider.notifier);
      final filter = container.read(
        elaborationDiagnosticFilterProvider.notifier,
      );

      expect(
        await timed(tester, 'show ${warnings + infos} entries', () {
          stderr.set(stderrText());
        }),
        lessThan(budget),
      );
      expect(
        container.read(elaborationDiagnosticsProvider),
        hasLength(warnings + infos),
      );

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final position = scrollable.position;

      expect(
        await timed(tester, 'jump to the middle', () {
          position.jumpTo(position.maxScrollExtent / 2);
        }),
        lessThan(budget),
      );
      expect(
        await timed(tester, 'jump to the end', () {
          position.jumpTo(position.maxScrollExtent);
        }),
        lessThan(budget),
      );
      expect(find.textContaining('top.v:${infos - 1}:'), findsOneWidget);

      // Hiding the entries the list is scrolled among leaves a list that is
      // half as long, so the offset it is at is moved to the new end.
      expect(
        await timed(tester, 'hide the info entries at the end', () {
          filter.toggle(YosysDiagnosticSeverity.info);
        }),
        lessThan(budget),
      );
      expect(find.textContaining('top.u${warnings - 1}.'), findsOneWidget);
      expect(
        await timed(tester, 'show them again', () {
          filter.toggle(YosysDiagnosticSeverity.info);
        }),
        lessThan(budget),
      );
      expect(
        await timed(tester, 'jump to the end again', () {
          final again = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          again.jumpTo(again.maxScrollExtent);
        }),
        lessThan(budget),
      );
      expect(
        await timed(tester, 'clear every entry', stderr.clear),
        lessThan(budget),
      );
      expect(
        find.text(
          L10N
              .of(tester.element(find.byType(TabDiagnosticsDrawer)))
              .elaborationDiagnosticsEmpty,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'every row is the same height, so a row is placed by arithmetic',
    (
      tester,
    ) async {
      final container = await pumpDrawer(tester);
      container
          .read(elaborationStderrProvider.notifier)
          .set(
            'Warning: no location, and a message long enough to need '
            'more than the one line of a location row ${'x' * 400}\n'
            'Warning: top.v:12: has a location\n',
          );
      await tester.pump();
      final heights = <double>{
        for (final tile in find.byType(ListTile).evaluate())
          tester.getSize(find.byWidget(tile.widget)).height,
      };
      expect(heights, <double>{TabDiagnosticsDrawer.kDiagnosticRowExtent});
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.itemExtent, TabDiagnosticsDrawer.kDiagnosticRowExtent);
    },
  );
}
