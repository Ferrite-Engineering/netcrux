// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';

void main() {
  group('ElementChange', () {
    const id = ElementId(kind: ElementKind.instance, path: 'top.alu:cell');

    test('round-trips through JSON for added rows', () {
      const c = ElementChange(
        kind: ElementChangeKind.added,
        elementKind: NetlistDiffElementKind.instance,
        elementId: id,
        comparisonSnapshot: <String, String>{'type': r'$and'},
      );
      final json = c.toJson();
      final restored = ElementChange.fromJson(json);
      expect(restored, equals(c));
    });

    test('round-trips through JSON for modified rows', () {
      const c = ElementChange(
        kind: ElementChangeKind.modified,
        elementKind: NetlistDiffElementKind.net,
        elementId: id,
        baselineSnapshot: <String, String>{'width': '8'},
        comparisonSnapshot: <String, String>{'width': '16'},
        modifiedAttributes: <String>['width'],
      );
      final restored = ElementChange.fromJson(c.toJson());
      expect(restored, equals(c));
      expect(restored.modifiedAttributes, equals(<String>['width']));
    });

    test('equality is value-based across all fields', () {
      const a = ElementChange(
        kind: ElementChangeKind.removed,
        elementKind: NetlistDiffElementKind.port,
        elementId: id,
        baselineSnapshot: <String, String>{'dir': 'input'},
      );
      const b = ElementChange(
        kind: ElementChangeKind.removed,
        elementKind: NetlistDiffElementKind.port,
        elementId: id,
        baselineSnapshot: <String, String>{'dir': 'input'},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith replaces fields cleanly', () {
      const c = ElementChange(
        kind: ElementChangeKind.unchanged,
        elementKind: NetlistDiffElementKind.module,
        elementId: id,
      );
      final c2 = c.copyWith(kind: ElementChangeKind.modified);
      expect(c2.kind, ElementChangeKind.modified);
      expect(c2.elementId, id);
    });
  });
}
