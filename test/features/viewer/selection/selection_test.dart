// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';

void main() {
  group('Selection', () {
    test('empty is empty', () {
      expect(Selection.empty.isEmpty, isTrue);
      expect(Selection.empty.isNotEmpty, isFalse);
      expect(Selection.empty.length, 0);
      expect(Selection.empty.primary, const SelectedElement.none());
    });

    test('single() wraps a non-none element', () {
      const element = SelectedElement.cell(cellId: 'u_alu');
      final s = Selection.single(element);
      expect(s.isEmpty, isFalse);
      expect(s.length, 1);
      expect(s.primary, element);
      expect(s.contains(element), isTrue);
      expect(s.isPrimary(element), isTrue);
    });

    test('single(none) returns empty', () {
      expect(
        Selection.single(const SelectedElement.none()),
        Selection.empty,
      );
    });

    test('addElement appends and promotes primary', () {
      const a = SelectedElement.cell(cellId: 'a');
      const b = SelectedElement.cell(cellId: 'b');
      final s = Selection.single(a).addElement(b);
      expect(s.length, 2);
      expect(s.primary, b);
      expect(s.contains(a), isTrue);
      expect(s.contains(b), isTrue);
    });

    test('addElement on the existing primary is a no-op', () {
      const a = SelectedElement.cell(cellId: 'a');
      final s = Selection.single(a);
      expect(identical(s.addElement(a), s), isTrue);
    });

    test('addElement on a non-primary existing element re-anchors primary', () {
      const a = SelectedElement.cell(cellId: 'a');
      const b = SelectedElement.cell(cellId: 'b');
      final s = Selection.single(a).addElement(b);
      // s.primary == b now. Re-add a → length stays 2, primary becomes a.
      final next = s.addElement(a);
      expect(next.length, 2);
      expect(next.primary, a);
    });

    test('toggleElement removes existing', () {
      const a = SelectedElement.cell(cellId: 'a');
      expect(
        Selection.single(a).toggleElement(a),
        Selection.empty,
      );
    });

    test('toggleElement on missing adds and promotes', () {
      const a = SelectedElement.cell(cellId: 'a');
      const b = SelectedElement.cell(cellId: 'b');
      final s = Selection.single(a).toggleElement(b);
      expect(s.length, 2);
      expect(s.primary, b);
    });

    test('toggleElement removing the primary picks a new primary', () {
      const a = SelectedElement.cell(cellId: 'a');
      const b = SelectedElement.cell(cellId: 'b');
      final s = Selection.single(a).addElement(b); // primary = b
      final next = s.toggleElement(b); // remove the primary
      expect(next.length, 1);
      expect(next.primary, a);
    });

    test('toggleElement on none is a no-op', () {
      const a = SelectedElement.cell(cellId: 'a');
      final s = Selection.single(a);
      expect(
        identical(s.toggleElement(const SelectedElement.none()), s),
        isTrue,
      );
    });

    test('withPrimary promotes an existing element', () {
      const a = SelectedElement.cell(cellId: 'a');
      const b = SelectedElement.cell(cellId: 'b');
      final s = Selection.single(a).addElement(b);
      expect(s.withPrimary(a).primary, a);
    });

    test('withPrimary adds the element when not present', () {
      const a = SelectedElement.cell(cellId: 'a');
      const b = SelectedElement.cell(cellId: 'b');
      final next = Selection.single(a).withPrimary(b);
      expect(next.length, 2);
      expect(next.primary, b);
    });

    test('withPrimary(none) collapses to empty', () {
      const a = SelectedElement.cell(cellId: 'a');
      expect(
        Selection.single(a).withPrimary(const SelectedElement.none()),
        Selection.empty,
      );
    });

    test('equality is value-based', () {
      const a = SelectedElement.cell(cellId: 'a');
      const b = SelectedElement.cell(cellId: 'b');
      final s1 = Selection.single(a).addElement(b);
      final s2 = Selection.single(a).addElement(b);
      expect(s1, s2);
      expect(s1.hashCode, s2.hashCode);
    });

    test('equality cares about primary', () {
      const a = SelectedElement.cell(cellId: 'a');
      const b = SelectedElement.cell(cellId: 'b');
      final s1 = Selection.single(a).addElement(b);
      // primary == b
      final s2 = Selection(
        elements: <SelectedElement>{a, b},
        primary: a,
      );
      expect(s1 == s2, isFalse);
    });
  });
}
