// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_request.dart';
import 'package:netcrux/features/diff/providers/diff_pane_state_provider.dart';
import 'package:netcrux/features/diff/widgets/diff_pane.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

NetlistDiff _seed() => NetlistDiff(
  baselineNetlist: const NetlistRef(identifier: 'a'),
  comparisonNetlist: const NetlistRef(identifier: 'b'),
  generatedAt: DateTime.utc(2026, 5, 25),
  elementChanges: const <ElementChange>[
    ElementChange(
      kind: ElementChangeKind.added,
      elementKind: NetlistDiffElementKind.instance,
      elementId: ElementId(kind: ElementKind.instance, path: 'top.alu'),
    ),
    ElementChange(
      kind: ElementChangeKind.removed,
      elementKind: NetlistDiffElementKind.net,
      elementId: ElementId(kind: ElementKind.net, path: 'top:net:foo'),
    ),
    ElementChange(
      kind: ElementChangeKind.modified,
      elementKind: NetlistDiffElementKind.port,
      elementId: ElementId(kind: ElementKind.port, path: 'top.in'),
      modifiedAttributes: <String>['direction'],
    ),
  ],
);

class _SeededNotifier extends DiffPaneStateNotifier {
  _SeededNotifier(this._seed);
  final NetlistDiff _seed;

  @override
  DiffPaneState build() => DiffPaneState(
    activeRequest: const NetlistDiffRequest(
      baselineNetlist: NetlistRef(identifier: 'a'),
      comparisonNetlist: NetlistRef(identifier: 'b'),
    ),
    activeDiff: _seed,
  );
}

Widget _wrap(
  Widget child, {
  Locale locale = const Locale('en'),
  NetlistDiff? seeded,
  void Function(ElementChange)? onShowInSchematic,
}) {
  return ProviderScope(
    overrides: <Override>[
      if (seeded != null)
        diffPaneStateProvider.overrideWith(
          () => _SeededNotifier(seeded),
        ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<Object?>>[
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ],
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 500,
          child: DiffPane(onShowInSchematic: onShowInSchematic),
        ),
      ),
    ),
  );
}

void main() {
  group('DiffPane', () {
    testWidgets('renders empty state when no comparison is active', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const DiffPane()));
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      // Title + hint render as one CruxPanelEmptyState message.
      expect(find.textContaining(l10n.diffPaneEmptyTitle), findsOneWidget);
      expect(find.textContaining(l10n.diffPaneEmptyHint), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders summary header + grouped change list when seeded', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const DiffPane(), seeded: _seed()));
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      // Summary header
      expect(
        find.text(l10n.diffPaneSummary(1, 1, 1, 0)),
        findsOneWidget,
      );
      // Each group header
      expect(find.text(l10n.diffPaneGroupAdded(1)), findsOneWidget);
      expect(find.text(l10n.diffPaneGroupRemoved(1)), findsOneWidget);
      expect(find.text(l10n.diffPaneGroupModified(1)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Show in Schematic invokes the callback', (tester) async {
      ElementChange? captured;
      await tester.pumpWidget(
        _wrap(
          const DiffPane(),
          seeded: _seed(),
          onShowInSchematic: (c) => captured = c,
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      final btn = find.text(l10n.diffPaneShowInSchematic).first;
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
    });

    for (final locale in const <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('locale sweep — empty state renders in $locale', (
        tester,
      ) async {
        await tester.pumpWidget(_wrap(const DiffPane(), locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('locale sweep — loaded state renders in $locale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            const DiffPane(),
            locale: locale,
            seeded: _seed(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
