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
  double width = 600,
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
          width: width,
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
      // Rows are listed added, removed, modified: the second button is the
      // removed net's.
      final btn = find.text(l10n.diffPaneShowInSchematic).at(1);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(captured?.elementId.path, 'top:net:foo');
      // It also makes its row the active one, so the footer counter and
      // the row highlight name the element the schematic shows.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DiffPane)),
      );
      expect(container.read(diffPaneStateProvider).selectedChangeIndex, 1);
    });

    testWidgets('an added row is not on the schematic: its Show in Schematic '
        'is disabled and its tooltip says why', (tester) async {
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
      final added = find.ancestor(
        of: find.text(l10n.diffPaneShowInSchematic).first,
        matching: find.byType(TextButton),
      );
      expect(tester.widget<TextButton>(added).onPressed, isNull);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: added, matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, l10n.diffPaneShowInSchematicComparisonOnly);
      await tester.tap(added, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(captured, isNull);
    });

    testWidgets('without a host there is no Show in Schematic', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const DiffPane(), seeded: _seed()));
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.diffPaneShowInSchematic), findsNothing);
    });

    testWidgets('clicking a row shows its element, and again on a second '
        'click', (tester) async {
      final captured = <ElementChange>[];
      await tester.pumpWidget(
        _wrap(
          const DiffPane(),
          seeded: _seed(),
          onShowInSchematic: captured.add,
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DiffPane)),
      );
      // The row click is the primary reveal. It selects the
      // row and hands the host exactly that row's change, not one looked up
      // again by index.
      await tester.tap(find.text('foo'));
      await tester.pumpAndSettle();
      expect(captured.single.elementId.path, 'top:net:foo');
      expect(container.read(diffPaneStateProvider).selectedChangeIndex, 1);
      await tester.tap(find.text('foo'));
      await tester.pumpAndSettle();
      expect(captured.map((c) => c.elementId.path), <String>[
        'top:net:foo',
        'top:net:foo',
      ]);
    });

    testWidgets('clicking an added row selects it and shows nothing', (
      tester,
    ) async {
      final captured = <ElementChange>[];
      await tester.pumpWidget(
        _wrap(
          const DiffPane(),
          seeded: _seed(),
          onShowInSchematic: captured.add,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('top.alu').first);
      await tester.pumpAndSettle();
      expect(captured, isEmpty);
    });

    group('at a narrow width', () {
      NetlistDiff longNames() => NetlistDiff(
        baselineNetlist: const NetlistRef(identifier: 'a'),
        comparisonNetlist: const NetlistRef(identifier: 'b'),
        generatedAt: DateTime.utc(2026, 10, 5),
        elementChanges: const <ElementChange>[
          ElementChange(
            kind: ElementChangeKind.added,
            elementKind: NetlistDiffElementKind.instance,
            elementId: ElementId(
              kind: ElementKind.instance,
              path: 'top.u_a_very_long_instance_name_that_cannot_fit:cell',
            ),
          ),
          ElementChange(
            kind: ElementChangeKind.removed,
            elementKind: NetlistDiffElementKind.net,
            elementId: ElementId(
              kind: ElementKind.net,
              path:
                  r'gray_counter:net:$add$/Users/me/Getting$20Started$20Videos'
                  r'/NetCrux/Assets/gray_counter.v:15$5_Y',
            ),
          ),
        ],
      );

      for (final width in const <double>[200, 280, 360]) {
        testWidgets('${width.toInt()} px: the icon button stays inside the '
            'row and the name truncates', (tester) async {
          final captured = <ElementChange>[];
          await tester.pumpWidget(
            _wrap(
              const DiffPane(),
              seeded: longNames(),
              onShowInSchematic: captured.add,
              width: width,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final l10n = await L10N.delegate.load(const Locale('en'));
          // Icon only: the label is the tooltip.
          expect(find.text(l10n.diffPaneShowInSchematic), findsNothing);
          final icons = find.byIcon(Icons.center_focus_strong);
          expect(icons, findsNWidgets(2));
          for (var i = 0; i < 2; i++) {
            final rect = tester.getRect(icons.at(i));
            expect(rect.right, lessThanOrEqualTo(width), reason: 'row $i');
            expect(rect.left, greaterThan(width / 2), reason: 'row $i');
          }
          // The enabled one says what it does; the added row's says why
          // it is disabled.
          expect(find.byTooltip(l10n.diffPaneShowInSchematic), findsOneWidget);
          expect(
            find.byTooltip(l10n.diffPaneShowInSchematicComparisonOnly),
            findsOneWidget,
          );
          final added = find.ancestor(
            of: icons.at(0),
            matching: find.byType(IconButton),
          );
          expect(tester.widget<IconButton>(added).onPressed, isNull);
          await tester.tap(icons.at(1));
          await tester.pumpAndSettle();
          expect(captured.single.elementKind, NetlistDiffElementKind.net);
          // The net reads like a cell row, with no `$20` left in it.
          expect(
            find.text(r'$add  gray_counter.v:15  (Y)'),
            findsOneWidget,
          );
        });
      }

      testWidgets('the button keeps its place whatever the name length', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            const DiffPane(),
            seeded: longNames(),
            onShowInSchematic: (_) {},
            width: 280,
          ),
        );
        await tester.pumpAndSettle();
        final icons = find.byIcon(Icons.center_focus_strong);
        expect(
          tester.getRect(icons.at(0)).right,
          tester.getRect(icons.at(1)).right,
        );
      });
    });

    testWidgets('a wide row shows the label beside the icon', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DiffPane(),
          seeded: _seed(),
          onShowInSchematic: (_) {},
          width: DiffPane.showInSchematicLabelMinWidth + 40,
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.diffPaneShowInSchematic), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a generated cell shows its type and file:line', (
      tester,
    ) async {
      final diff = NetlistDiff(
        baselineNetlist: const NetlistRef(identifier: 'a'),
        comparisonNetlist: const NetlistRef(identifier: 'b'),
        generatedAt: DateTime.utc(2026, 10, 5),
        elementChanges: const <ElementChange>[
          ElementChange(
            kind: ElementChangeKind.removed,
            elementKind: NetlistDiffElementKind.instance,
            elementId: ElementId(
              kind: ElementKind.instance,
              path: r'gray_counter.$xor$/home/me/rtl/gray_counter.v:15$7:cell',
            ),
            baselineSnapshot: <String, String>{'type': r'$xor'},
            sourceLocation: '/home/me/rtl/gray_counter.v:15.21-15.55',
          ),
        ],
      );
      await tester.pumpWidget(_wrap(const DiffPane(), seeded: diff));
      await tester.pumpAndSettle();
      expect(find.text(r'$xor  gray_counter.v:15'), findsOneWidget);
      expect(find.text('gray_counter'), findsOneWidget);
      // The full path is in the tooltip, not on the row.
      expect(find.textContaining('/home/me/rtl'), findsNothing);
      final tooltip = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.text(r'$xor  gray_counter.v:15'),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(tooltip.message, contains('/home/me/rtl/gray_counter.v:15'));
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
