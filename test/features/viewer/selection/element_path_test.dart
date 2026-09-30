// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/selection/element_path.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';

void main() {
  group('buildElementPath', () {
    const top = HierarchyNode(path: <String>[], moduleName: 'top');
    const cpu = HierarchyNode(path: <String>['u_cpu'], moduleName: 'cpu');

    test('none returns null', () {
      expect(
        buildElementPath(
          topModuleName: 'top',
          scope: top,
          element: const SelectedElement.none(),
        ),
        isNull,
      );
    });

    test('cell at the root prefixes with the top module name', () {
      expect(
        buildElementPath(
          topModuleName: 'top',
          scope: top,
          element: const SelectedElement.cell(cellId: 'u_alu'),
        ),
        'top.u_alu:cell',
      );
    });

    test('cell inside a scope chains instance names', () {
      expect(
        buildElementPath(
          topModuleName: 'top',
          scope: cpu,
          element: const SelectedElement.cell(cellId: 'u_alu'),
        ),
        'top.u_cpu.u_alu:cell',
      );
    });

    test('port path uses dot + portName', () {
      expect(
        buildElementPath(
          topModuleName: 'top',
          scope: cpu,
          element: const SelectedElement.port(
            cellId: 'u_alu',
            portId: 'u_alu:Y',
            portName: 'Y',
          ),
        ),
        'top.u_cpu.u_alu.Y',
      );
    });

    test('boundary port uses :port: tag', () {
      expect(
        buildElementPath(
          topModuleName: 'top',
          scope: cpu,
          element: const SelectedElement.boundaryPort(
            portId: 'port:clk',
            portName: 'clk',
          ),
        ),
        'top.u_cpu:port:clk',
      );
    });

    test('wire uses :net: tag with the edge id', () {
      expect(
        buildElementPath(
          topModuleName: 'top',
          scope: cpu,
          element: const SelectedElement.wire(edgeId: 'e42', netId: 42),
        ),
        'top.u_cpu:net:e42',
      );
    });
  });
}
