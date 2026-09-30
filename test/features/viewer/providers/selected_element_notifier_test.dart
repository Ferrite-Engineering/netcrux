// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';

void main() {
  group('SelectedElementNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is empty', () {
      expect(container.read(selectedElementProvider), Selection.empty);
    });

    test('select replaces state with a single-element selection', () {
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_alu'));
      expect(
        container.read(selectedElementProvider),
        Selection.single(const SelectedElement.cell(cellId: 'u_alu')),
      );
    });

    test('select(none) clears the selection', () {
      container.read(selectedElementProvider.notifier)
        ..select(const SelectedElement.cell(cellId: 'x'))
        ..select(const SelectedElement.none());
      expect(container.read(selectedElementProvider), Selection.empty);
    });

    test('toggleInSelection removes existing, adds missing', () {
      const elem = SelectedElement.cell(cellId: 'u_alu');
      container.read(selectedElementProvider.notifier)
        ..toggleInSelection(elem)
        ..toggleInSelection(elem);
      expect(container.read(selectedElementProvider), Selection.empty);
    });

    test('toggleInSelection keeps both elements when different', () {
      container.read(selectedElementProvider.notifier)
        ..toggleInSelection(const SelectedElement.cell(cellId: 'a'))
        ..toggleInSelection(const SelectedElement.cell(cellId: 'b'));
      final state = container.read(selectedElementProvider);
      expect(state.length, 2);
      expect(
        state.contains(const SelectedElement.cell(cellId: 'a')),
        isTrue,
      );
      expect(
        state.contains(const SelectedElement.cell(cellId: 'b')),
        isTrue,
      );
      // The most recent click becomes the primary anchor.
      expect(state.primary, const SelectedElement.cell(cellId: 'b'));
    });

    test('addToSelection adds without removing and promotes primary', () {
      container.read(selectedElementProvider.notifier)
        ..select(const SelectedElement.cell(cellId: 'a'))
        ..addToSelection(const SelectedElement.cell(cellId: 'b'));
      final state = container.read(selectedElementProvider);
      expect(state.length, 2);
      expect(state.primary, const SelectedElement.cell(cellId: 'b'));
    });

    test(
      'addToSelection on an already-selected element re-anchors primary',
      () {
        container.read(selectedElementProvider.notifier)
          ..select(const SelectedElement.cell(cellId: 'a'))
          ..addToSelection(const SelectedElement.cell(cellId: 'b'))
          ..addToSelection(const SelectedElement.cell(cellId: 'a'));
        final state = container.read(selectedElementProvider);
        expect(state.length, 2);
        expect(state.primary, const SelectedElement.cell(cellId: 'a'));
      },
    );

    test('clear drops back to empty', () {
      container.read(selectedElementProvider.notifier)
        ..select(const SelectedElement.cell(cellId: 'x'))
        ..clear();
      expect(container.read(selectedElementProvider), Selection.empty);
    });

    test('replace installs an arbitrary selection verbatim', () {
      final notifier = container.read(selectedElementProvider.notifier);
      final selection = Selection(
        elements: <SelectedElement>{
          const SelectedElement.cell(cellId: 'a'),
          const SelectedElement.cell(cellId: 'b'),
        },
        primary: const SelectedElement.cell(cellId: 'a'),
      );
      notifier.replace(selection);
      expect(container.read(selectedElementProvider), selection);
    });
  });
}
