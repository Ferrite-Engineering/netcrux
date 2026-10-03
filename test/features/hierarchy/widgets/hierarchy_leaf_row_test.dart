// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_leaf_row.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_row.dart';

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
}
