// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';

void main() {
  group('SelectedElement', () {
    test('none equality / hashCode', () {
      expect(
        const SelectedElement.none(),
        equals(const SelectedElement.none()),
      );
      expect(const SelectedElement.none().isNone, isTrue);
      expect(
        const SelectedElement.none().hashCode,
        const SelectedElement.none().hashCode,
      );
    });

    test('cell equality / hashCode', () {
      expect(
        const SelectedElement.cell(cellId: 'u_alu'),
        equals(const SelectedElement.cell(cellId: 'u_alu')),
      );
      expect(
        const SelectedElement.cell(cellId: 'u_alu'),
        isNot(equals(const SelectedElement.cell(cellId: 'u_cpu'))),
      );
    });

    test('port equality / hashCode', () {
      const a = SelectedElement.port(
        cellId: 'u_alu',
        portId: 'u_alu:Y',
        portName: 'Y',
      );
      const b = SelectedElement.port(
        cellId: 'u_alu',
        portId: 'u_alu:Y',
        portName: 'Y',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('boundaryPort equality', () {
      expect(
        const SelectedElement.boundaryPort(portId: 'port:clk', portName: 'clk'),
        equals(
          const SelectedElement.boundaryPort(
            portId: 'port:clk',
            portName: 'clk',
          ),
        ),
      );
    });

    test('wire equality', () {
      expect(
        const SelectedElement.wire(edgeId: 'e_1_0', netId: 1),
        equals(const SelectedElement.wire(edgeId: 'e_1_0', netId: 1)),
      );
    });

    test('isNone is only true for the none variant', () {
      expect(const SelectedElement.cell(cellId: 'x').isNone, isFalse);
      expect(
        const SelectedElement.port(
          cellId: 'x',
          portId: 'x:y',
          portName: 'y',
        ).isNone,
        isFalse,
      );
    });
  });
}
