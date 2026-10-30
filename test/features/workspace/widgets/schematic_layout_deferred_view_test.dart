// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/schematic/scope_layout_gate.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/layout_approval_notifier.dart';
import 'package:netcrux/features/workspace/widgets/schematic_layout_deferred_view.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

const _gate = ScopeLayoutGate(cellCount: 844208, limit: 40000);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Locale locale,
  ScopeLayoutGate gate = _gate,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container
      .read(hierarchyTreeProvider.notifier)
      .setModel(
        const NetlistModel(
          creator: 'test',
          modules: <String, Module>{
            'top': Module(
              name: 'top',
              attributes: <String, String>{'top': '1'},
              ports: <String, Port>{},
              cells: <String, Cell>{},
              nets: <String, Net>{},
            ),
          },
        ),
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: SchematicLayoutDeferredView(gate: gate)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('SchematicLayoutDeferredView', () {
    for (final locale in _locales) {
      final tag = locale.countryCode == null
          ? locale.languageCode
          : '${locale.languageCode}_${locale.countryCode}';

      testWidgets('[$tag] says the size, the way forward and the cost', (
        tester,
      ) async {
        final l10n = await L10N.delegate.load(locale);
        await _pump(tester, locale: locale);
        expect(find.text(l10n.schematicLayoutDeferredTitle), findsOneWidget);
        expect(
          find.text(l10n.schematicLayoutDeferredBody('top', 844208, 40000)),
          findsOneWidget,
        );
        expect(find.text(l10n.schematicLayoutDeferredCone), findsOneWidget);
        expect(find.text(l10n.schematicLayoutDeferredAction), findsOneWidget);
        // 844,208 cells at 130 KiB a cell: about 105 GB.
        expect(
          find.text(l10n.schematicLayoutDeferredEstimate('105 GB')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the cell counts are shown with digit grouping', (
      tester,
    ) async {
      await _pump(tester, locale: const Locale('en'));
      expect(find.textContaining('844,208'), findsOneWidget);
      expect(find.textContaining('40,000'), findsOneWidget);
    });

    testWidgets('Lay out anyway approves the scope on show', (tester) async {
      final container = await _pump(tester, locale: const Locale('en'));
      expect(container.read(layoutApprovalProvider), isEmpty);
      await tester.tap(find.byKey(SchematicLayoutDeferredView.layOutAnywayKey));
      await tester.pump();
      expect(
        container.read(layoutApprovalProvider),
        <HierarchyNode>{container.read(hierarchyTreeProvider).selected!},
      );
    });

    testWidgets('a focus walk lands on the one named button and cycles', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, locale: const Locale('en'));
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk, context: 'the held-back scope');
      expect(walk.stops, hasLength(1));
      expect(walk.stops.single.name, 'Lay out anyway');
      handle.dispose();
    });

    testWidgets('the button is reachable by keyboard and named', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, locale: const Locale('en'));
      expect(
        tester.getSemantics(
          find.byKey(SchematicLayoutDeferredView.layOutAnywayKey),
        ),
        matchesSemantics(
          label: 'Lay out anyway',
          isButton: true,
          isEnabled: true,
          isFocusable: true,
          hasEnabledState: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('formatLayoutMemoryEstimate', () {
    test('keeps a tenth of a gigabyte below 10 GB', () {
      expect(formatLayoutMemoryEstimate(5 * 1024 * 1024 * 1024), '5.0 GB');
      expect(formatLayoutMemoryEstimate(300 * 1024 * 1024), '300 MB');
    });

    test('rounds to whole gigabytes from 10 GB', () {
      expect(
        formatLayoutMemoryEstimate(estimateLayoutBytes(844208)),
        '105 GB',
      );
      expect(
        formatLayoutMemoryEstimate(10 * 1024 * 1024 * 1024),
        '10 GB',
      );
    });
  });
}
