// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/panel_layout_state.dart';

void main() {
  group('PanelLayoutState', () {
    test('default constructor preserves NetCrux launch experience', () {
      const s = PanelLayoutState();
      // Hierarchy docked; inspector + diagnostics collapsed (opened on
      // demand from the View menu / command palette).
      expect(s.hierarchyTreeVisible, isTrue);
      expect(s.inspectorVisible, isFalse);
      expect(s.diagnosticsVisible, isFalse);
      expect(s.hierarchyTreeWidth, isNull);
      expect(s.inspectorWidth, isNull);
      expect(s.diagnosticsHeight, isNull);
    });

    test('copyWith replaces selected fields verbatim', () {
      const original = PanelLayoutState();
      final next = original.copyWith(
        inspectorVisible: true,
        hierarchyTreeWidth: 240,
      );
      expect(next.inspectorVisible, isTrue);
      expect(next.hierarchyTreeWidth, 240);
      // Untouched fields preserved.
      expect(next.hierarchyTreeVisible, isTrue);
      expect(next.diagnosticsVisible, isFalse);
    });

    test('copyWith — clear flags reset optional sizes to null', () {
      const sized = PanelLayoutState(
        hierarchyTreeWidth: 240,
        inspectorWidth: 320,
        diagnosticsHeight: 200,
      );
      final cleared = sized.copyWith(
        clearHierarchyTreeWidth: true,
        clearInspectorWidth: true,
        clearDiagnosticsHeight: true,
      );
      expect(cleared.hierarchyTreeWidth, isNull);
      expect(cleared.inspectorWidth, isNull);
      expect(cleared.diagnosticsHeight, isNull);
    });

    test('copyWith — clear flag wins over a non-null replacement', () {
      const original = PanelLayoutState(hierarchyTreeWidth: 250);
      final cleared = original.copyWith(
        hierarchyTreeWidth: 400,
        clearHierarchyTreeWidth: true,
      );
      expect(cleared.hierarchyTreeWidth, isNull);
    });

    test('== is structural across every field', () {
      const a = PanelLayoutState(
        inspectorVisible: true,
        hierarchyTreeWidth: 240,
      );
      const b = PanelLayoutState(
        inspectorVisible: true,
        hierarchyTreeWidth: 240,
      );
      const c = PanelLayoutState(hierarchyTreeWidth: 240);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('toString includes every visibility and size field', () {
      const s = PanelLayoutState(
        inspectorVisible: true,
        diagnosticsHeight: 200,
      );
      final out = s.toString();
      expect(out, contains('hierarchyTreeVisible: true'));
      expect(out, contains('inspectorVisible: true'));
      expect(out, contains('diagnosticsHeight: 200'));
    });
  });
}
