// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_leaf_row.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_row.dart';
import 'package:netcrux/shared/widgets/start_ellipsis_text.dart';

void main() {
  Future<FocusNode> pump(
    WidgetTester tester, {
    required VoidCallback onActivate,
    bool isSelected = false,
  }) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HierarchyLeafRow(
            depth: 1,
            icon: Icons.memory_outlined,
            label: 'add_cy_3',
            detail: 'SB_LUT4',
            semanticLabel: 'Cell add_cy_3, type SB_LUT4',
            isSelected: isSelected,
            focusNode: node,
            onActivate: onActivate,
          ),
        ),
      ),
    );
    return node;
  }

  testWidgets('shows the label and the detail at the tree row height', (
    tester,
  ) async {
    await pump(tester, onActivate: () {});
    expect(find.text('add_cy_3'), findsOneWidget);
    expect(find.text('SB_LUT4'), findsOneWidget);
    expect(
      tester.getSize(find.byType(HierarchyLeafRow)).height,
      HierarchyTreeRow.rowHeight,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a click activates it and takes focus', (tester) async {
    var activations = 0;
    final node = await pump(tester, onActivate: () => activations++);
    await tester.tap(find.byType(HierarchyLeafRow));
    await tester.pump();
    expect(activations, 1);
    expect(node.hasPrimaryFocus, isTrue);
  });

  testWidgets('Enter and Space activate the focused row', (tester) async {
    var activations = 0;
    final node = await pump(tester, onActivate: () => activations++);
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activations, 2);
  });

  testWidgets('is one named button node carrying its selected state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, onActivate: () {}, isSelected: true);
    final semantics = tester.getSemantics(
      find.bySemanticsLabel('Cell add_cy_3, type SB_LUT4'),
    );
    expect(
      semantics,
      matchesSemantics(
        label: 'Cell add_cy_3, type SB_LUT4',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    // The visible text is not a second node.
    expect(find.bySemanticsLabel('add_cy_3'), findsNothing);
    handle.dispose();
  });

  group('a long cell name', () {
    const name = 'servant.servile.cpu.alu.add_cy_r_SB_LUT4_I3_1';
    const semanticLabel = 'Cell $name, type SB_LUT4';

    Future<void> pumpNarrow(
      WidgetTester tester, {
      bool elideLabelStart = true,
      String? tooltip = name,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 480,
                child: HierarchyLeafRow(
                  depth: 1,
                  icon: Icons.memory_outlined,
                  label: name,
                  detail: 'SB_LUT4',
                  semanticLabel: semanticLabel,
                  elideLabelStart: elideLabelStart,
                  tooltip: tooltip,
                  onActivate: () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    String shownLabel(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(HierarchyLeafRow),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data!)
        .firstWhere((d) => d != 'SB_LUT4');

    testWidgets('keeps its tail and the type column', (tester) async {
      await pumpNarrow(tester);
      final shown = shownLabel(tester);
      expect(shown, startsWith(startEllipsis));
      expect(shown, endsWith('add_cy_r_SB_LUT4_I3_1'));
      expect(shown.length, lessThan(name.length));
      expect(find.text('SB_LUT4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a row without start elision cuts the end', (tester) async {
      await pumpNarrow(tester, elideLabelStart: false, tooltip: null);
      // The plain Text holds the full name and ellipsizes when painted.
      final text = tester.widget<Text>(find.text(name));
      expect(text.overflow, TextOverflow.ellipsis);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('shows the full name on hover', (tester) async {
      await pumpNarrow(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(HierarchyLeafRow)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(name), findsOneWidget);
      await gesture.moveTo(const Offset(600, 500));
      await tester.pumpAndSettle();
    });

    testWidgets('is still one node named in full', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpNarrow(tester);
      expect(find.bySemanticsLabel(semanticLabel), findsOneWidget);
      // Neither the elided text nor the tooltip is a second name.
      expect(find.bySemanticsLabel(RegExp(startEllipsis)), findsNothing);
      expect(find.bySemanticsLabel(name), findsNothing);
      handle.dispose();
    });
  });
}
