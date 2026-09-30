// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_row.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('HierarchyTreeRow', () {
    testWidgets('renders the instance name and module suffix', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(
          HierarchyTreeRow(
            node: const HierarchyNode(
              path: <String>['u_cpu'],
              moduleName: 'cpu',
            ),
            depth: 1,
            isExpanded: false,
            isSelected: false,
            hasChildren: true,
            cellCount: 5,
            instanceName: 'u_cpu',
            moduleName: 'cpu',
            onTap: () => tapped++,
            onToggleExpand: () {},
          ),
        ),
      );
      expect(find.textContaining('u_cpu'), findsOneWidget);
      expect(find.textContaining('cpu'), findsWidgets);
      expect(find.textContaining('5 cells'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('omits module suffix at the root', (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchyTreeRow(
            node: const HierarchyNode(path: <String>[], moduleName: 'top'),
            depth: 0,
            isExpanded: true,
            isSelected: false,
            hasChildren: true,
            cellCount: 3,
            instanceName: 'top',
            moduleName: 'top',
            onTap: () {},
            onToggleExpand: () {},
          ),
        ),
      );
      // Just the bare name + the cell count, no parens.
      expect(find.text('top'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders an empty chevron placeholder when leaf', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          HierarchyTreeRow(
            node: const HierarchyNode(
              path: <String>['u_alu'],
              moduleName: 'alu',
            ),
            depth: 1,
            isExpanded: false,
            isSelected: false,
            hasChildren: false,
            cellCount: 0,
            instanceName: 'u_alu',
            moduleName: 'alu',
            onTap: () {},
          ),
        ),
      );
      // No expand IconButton is rendered when there are no children.
      expect(find.byType(IconButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expand chevron fires the toggle callback', (tester) async {
      var toggled = 0;
      await tester.pumpWidget(
        _wrap(
          HierarchyTreeRow(
            node: const HierarchyNode(
              path: <String>['u_cpu'],
              moduleName: 'cpu',
            ),
            depth: 1,
            isExpanded: false,
            isSelected: false,
            hasChildren: true,
            cellCount: 2,
            instanceName: 'u_cpu',
            moduleName: 'cpu',
            onTap: () {},
            onToggleExpand: () => toggled++,
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(toggled, 1);
    });

    testWidgets('the row is one Tab stop and one named node; the chevron is '
        'for the pointer only', (tester) async {
      final handle = tester.ensureSemantics();
      var tapped = 0;
      var toggled = 0;
      await tester.pumpWidget(
        _wrap(
          HierarchyTreeRow(
            node: const HierarchyNode(
              path: <String>['u_cpu'],
              moduleName: 'cpu',
            ),
            depth: 1,
            isExpanded: false,
            isSelected: true,
            hasChildren: true,
            cellCount: 2,
            instanceName: 'u_cpu',
            moduleName: 'cpu',
            onTap: () => tapped++,
            onToggleExpand: () => toggled++,
          ),
        ),
      );

      final walk = await walkFocus(tester);
      expect(walk.stops, hasLength(1), reason: walk.transcript);
      expect(
        walk.stops.single.line,
        'u_cpu (cpu) 2 cells button collapsed selected',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(tapped, 2, reason: 'Enter and Space select the scope');
      expect(toggled, 0, reason: 'the chevron never takes the keyboard');

      // The pointer still has the chevron.
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(toggled, 1);

      // Keyboard focus draws a ring of its own, apart from the selection.
      final ring = tester.widget<DecoratedBox>(
        find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox && w.position == DecorationPosition.foreground,
        ),
      );
      expect((ring.decoration as BoxDecoration).border, isNotNull);
      handle.dispose();
    });

    testWidgets('a changed flashSignal pulses the row background then fades', (
      tester,
    ) async {
      Widget build(int? signal) => _wrap(
        HierarchyTreeRow(
          node: const HierarchyNode(path: <String>[], moduleName: 'top'),
          depth: 0,
          isExpanded: true,
          isSelected: false,
          hasChildren: true,
          cellCount: 3,
          instanceName: 'top',
          moduleName: 'top',
          onTap: () {},
          onToggleExpand: () {},
          flashSignal: signal,
        ),
      );

      Color? rowColor() => tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(HierarchyTreeRow),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color;

      // No flash yet: the unselected row's background is the transparent base.
      await tester.pumpWidget(build(null));
      expect(rowColor(), Colors.transparent);

      // A fresh flash token tints the background…
      await tester.pumpWidget(build(1));
      await tester.pump(const Duration(milliseconds: 40));
      final flashing = rowColor();
      expect(flashing, isNot(Colors.transparent));
      expect(flashing!.a, greaterThan(0));

      // …and the pulse fades back to the base colour.
      await tester.pumpAndSettle();
      expect(rowColor(), Colors.transparent);
      expect(tester.takeException(), isNull);
    });

    // Locale sweep — open-core convention: every interactive widget
    // pumps clean across en, zh_CN, zh, ja, ko so we catch RenderFlex
    // overflows and CJK font fallbacks before they ship.
    for (final locale in const <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders cleanly in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            HierarchyTreeRow(
              node: const HierarchyNode(
                path: <String>['u_cpu'],
                moduleName: 'cpu',
              ),
              depth: 1,
              isExpanded: false,
              isSelected: false,
              hasChildren: true,
              cellCount: 5,
              instanceName: 'u_cpu',
              moduleName: 'cpu',
              onTap: () {},
              onToggleExpand: () {},
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
