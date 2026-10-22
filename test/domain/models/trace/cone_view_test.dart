// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';

void main() {
  const top = HierarchyNode(path: <String>[], moduleName: 'top');
  const alu = HierarchyNode(path: <String>['u_alu'], moduleName: 'alu');
  const root = SelectedElement.cell(cellId: 'u_add');

  group('ConeViewRequest', () {
    test('defaults to fan-in at the default depth', () {
      const request = ConeViewRequest(scope: top, root: root);
      expect(request.direction, ConeViewDirection.fanIn);
      expect(request.depth, kDefaultConeViewDepth);
      expect(request.isTransitive, isFalse);
    });

    test('a null depth is the unlimited form', () {
      const request = ConeViewRequest(scope: top, root: root, depth: null);
      expect(request.isTransitive, isTrue);
    });

    test('is value-equal over scope, root, direction and depth', () {
      const a = ConeViewRequest(scope: top, root: root);
      const b = ConeViewRequest(scope: top, root: root);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const ConeViewRequest(scope: alu, root: root)));
      expect(
        a,
        isNot(
          const ConeViewRequest(
            scope: top,
            root: SelectedElement.cell(cellId: 'u_sub'),
          ),
        ),
      );
      expect(a, isNot(a.withDirection(ConeViewDirection.fanInAndFanOut)));
      expect(a, isNot(a.withDepth(3)));
    });

    test('withDirection and withDepth replace only their field', () {
      const a = ConeViewRequest(scope: alu, root: root, depth: 4);
      final both = a.withDirection(ConeViewDirection.fanInAndFanOut);
      expect(both.scope, alu);
      expect(both.root, root);
      expect(both.depth, 4);
      expect(both.direction, ConeViewDirection.fanInAndFanOut);
      final all = a.withDepth(null);
      expect(all.isTransitive, isTrue);
      expect(all.direction, ConeViewDirection.fanIn);
    });

    test('the offered depths start at one level and rise', () {
      expect(kConeViewDepths.first, 1);
      for (var i = 1; i < kConeViewDepths.length; i++) {
        expect(kConeViewDepths[i], greaterThan(kConeViewDepths[i - 1]));
      }
      expect(kConeViewDepths, contains(kDefaultConeViewDepth));
    });
  });

  group('ConeViewExtent', () {
    test('is value-equal over request and scope cell count', () {
      const request = ConeViewRequest(scope: top, root: root);
      const a = ConeViewExtent(request: request, scopeCellCount: 10);
      expect(a, const ConeViewExtent(request: request, scopeCellCount: 10));
      expect(
        a.hashCode,
        const ConeViewExtent(request: request, scopeCellCount: 10).hashCode,
      );
      expect(
        a,
        isNot(const ConeViewExtent(request: request, scopeCellCount: 11)),
      );
    });
  });
}
