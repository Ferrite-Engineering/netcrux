// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/links/services/netcrux_link_handler.dart';
import 'package:netcrux/features/links/widgets/open_link_confirm_dialog.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/links/netcrux_link.dart';

/// The confirmation a link raises for a file the user has not opened: it
/// names the file and its full path, starts with focus on Cancel so Enter or
/// Space on arrival opens nothing, treats Escape as Cancel, and opens only on
/// Open. And the messages the outcome of a link turns into.

const String _path = '/home/me/rtl/uart_tx.json';

/// The dialog's eventual answer, held so a test can act before awaiting it.
class _Answer {
  Future<bool>? future;
}

Future<_Answer> _open(WidgetTester tester, {Locale? locale}) async {
  final answer = _Answer();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
      ),
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () =>
                  answer.future = OpenLinkConfirmDialog.show(context, _path),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return answer;
}

Key? _focusedAction() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<CruxDialogAction>()
    ?.key;

void main() {
  SemanticsOrphanTestBinding.ensureInitialized();

  group('the dialog', () {
    testWidgets('names the file and the full path it will open', (
      tester,
    ) async {
      await _open(tester);
      expect(find.text('Open a design from a link?'), findsOneWidget);
      expect(find.textContaining('uart_tx.json'), findsWidgets);
      expect(find.text(_path), findsOneWidget);
    });

    testWidgets('focus starts on Cancel, and Enter there opens nothing', (
      tester,
    ) async {
      final answer = await _open(tester);
      expect(_focusedAction(), const ValueKey('linkConfirmCancel'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await answer.future, isFalse);
      expect(find.text(_path), findsNothing);
    });

    testWidgets('Space on arrival opens nothing', (tester) async {
      final answer = await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(await answer.future, isFalse);
    });

    testWidgets('Escape is Cancel', (tester) async {
      final answer = await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await answer.future, isFalse);
    });

    testWidgets('a click outside does not answer', (tester) async {
      await _open(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text(_path), findsOneWidget);
    });

    testWidgets('Open answers yes', (tester) async {
      final answer = await _open(tester);
      await tester.tap(find.byKey(const ValueKey('linkConfirmOpen')));
      await tester.pumpAndSettle();
      expect(await answer.future, isTrue);
    });

    testWidgets('Tab reaches Open from Cancel; activating it answers yes', (
      tester,
    ) async {
      final answer = await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedAction(), const ValueKey('linkConfirmOpen'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await answer.future, isTrue);
    });

    testWidgets('opens, answers and closes without an orphan semantics node', (
      tester,
    ) async {
      SemanticsOrphanGuard.instance.reset();
      final handle = tester.ensureSemantics();
      final answer = await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await answer.future, isFalse);
      handle.dispose();
      SemanticsOrphanGuard.instance.check(context: 'link confirmation');
      expect(SemanticsOrphanGuard.instance.updates, greaterThan(1));
    });

    testWidgets('lays out in every locale at the minimum window size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final locale in L10N.supportedLocales) {
        await _open(tester, locale: locale);
        expect(tester.takeException(), isNull, reason: '$locale');
        expect(find.text(_path), findsOneWidget, reason: '$locale');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    });
  });

  group('outcome messages', () {
    final l10n = lookupL10N(const Locale('en'));

    test('a refusal is an error that says why', () {
      final malformed = netCruxLinkOutcomeMessage(
        l10n,
        const NetCruxLinkOutcome.failed(
          NetCruxLinkFailure.malformed,
          parseRefusal: NetCruxLinkRefusal.unknownKey,
        ),
      )!;
      expect(malformed.error, isTrue);
      expect(malformed.message, l10n.linkRefusedMalformed);

      final relative = netCruxLinkOutcomeMessage(
        l10n,
        const NetCruxLinkOutcome.failed(
          NetCruxLinkFailure.pathRefused,
          parseRefusal: NetCruxLinkRefusal.relativePath,
        ),
      )!;
      expect(relative.message, l10n.linkRefusedPath);

      final missing = netCruxLinkOutcomeMessage(
        l10n,
        const NetCruxLinkOutcome.failed(
          NetCruxLinkFailure.fileNotFound,
          fileName: 'gone.v',
        ),
      )!;
      expect(missing.error, isTrue);
      expect(missing.message, contains('gone.v'));

      for (final failure in NetCruxLinkFailure.values) {
        expect(
          netCruxLinkOutcomeMessage(
            l10n,
            NetCruxLinkOutcome.failed(failure, fileName: 'x.v'),
          )?.error,
          isTrue,
          reason: '$failure',
        );
      }
    });

    test('a clean open, an open in a cone and a cancel say nothing', () {
      expect(
        netCruxLinkOutcomeMessage(
          l10n,
          const NetCruxLinkOutcome.opened(path: _path, openedTab: true),
        ),
        isNull,
      );
      expect(
        netCruxLinkOutcomeMessage(
          l10n,
          const NetCruxLinkOutcome.opened(
            path: _path,
            openedTab: true,
            kind: NetCruxLinkElementKind.cell,
            name: 'top.u',
            coneView: true,
          ),
        ),
        isNull,
      );
      expect(
        netCruxLinkOutcomeMessage(
          l10n,
          const NetCruxLinkOutcome.declined(path: _path),
        ),
        isNull,
      );
    });

    test('an element the design does not have is named, by its kind', () {
      final cell = netCruxLinkOutcomeMessage(
        l10n,
        const NetCruxLinkOutcome.opened(
          path: _path,
          openedTab: false,
          kind: NetCruxLinkElementKind.cell,
          name: 'top.nope',
          elementNotFound: true,
        ),
      )!;
      expect(cell.error, isFalse);
      expect(cell.message, l10n.linkCellNotFound('uart_tx.json', 'top.nope'));
      final net = netCruxLinkOutcomeMessage(
        l10n,
        const NetCruxLinkOutcome.opened(
          path: _path,
          openedTab: false,
          kind: NetCruxLinkElementKind.net,
          name: 'top.n',
          elementNotFound: true,
        ),
      )!;
      expect(net.message, l10n.linkNetNotFound('uart_tx.json', 'top.n'));
    });

    test('a long name is shortened before it is shown', () {
      final shown = netCruxLinkOutcomeMessage(
        l10n,
        NetCruxLinkOutcome.opened(
          path: _path,
          openedTab: true,
          kind: NetCruxLinkElementKind.cell,
          name: 's' * 1000,
          elementNotFound: true,
        ),
      )!;
      expect(shown.message.length, lessThan(300));
    });
  });
}
