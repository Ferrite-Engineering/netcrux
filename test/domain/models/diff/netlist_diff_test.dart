// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_request.dart';

void main() {
  group('NetlistDiff', () {
    const id = ElementId(kind: ElementKind.instance, path: 'top.x');

    test('empty diff has no elements and zero intensity', () {
      final d = NetlistDiff.empty();
      expect(d.elementChanges, isEmpty);
      expect(d.summary.modificationIntensity, 0.0);
      expect(d.isEmpty, isTrue);
      expect(d.isIdentical, isTrue);
    });

    test('isIdentical is true when only unchanged rows are present', () {
      final d = NetlistDiff(
        baselineNetlist: const NetlistRef(identifier: 'a'),
        comparisonNetlist: const NetlistRef(identifier: 'b'),
        generatedAt: DateTime.utc(2026, 5, 25),
        elementChanges: const <ElementChange>[
          ElementChange(
            kind: ElementChangeKind.unchanged,
            elementKind: NetlistDiffElementKind.instance,
            elementId: id,
          ),
        ],
      );
      expect(d.isIdentical, isTrue);
      expect(d.isEmpty, isFalse);
    });

    test('isIdentical is false when any non-unchanged row is present', () {
      final d = NetlistDiff(
        baselineNetlist: const NetlistRef(identifier: 'a'),
        comparisonNetlist: const NetlistRef(identifier: 'b'),
        generatedAt: DateTime.utc(2026, 5, 25),
        elementChanges: const <ElementChange>[
          ElementChange(
            kind: ElementChangeKind.modified,
            elementKind: NetlistDiffElementKind.net,
            elementId: id,
          ),
        ],
      );
      expect(d.isIdentical, isFalse);
    });

    test('summary is auto-computed when not supplied', () {
      final d = NetlistDiff(
        baselineNetlist: const NetlistRef(identifier: 'a'),
        comparisonNetlist: const NetlistRef(identifier: 'b'),
        generatedAt: DateTime.utc(2026, 5, 25),
        elementChanges: const <ElementChange>[
          ElementChange(
            kind: ElementChangeKind.added,
            elementKind: NetlistDiffElementKind.instance,
            elementId: id,
          ),
        ],
      );
      expect(d.summary.totalAdded, 1);
    });

    test('JSON round-trip preserves identity', () {
      final d = NetlistDiff(
        baselineNetlist: const NetlistRef(identifier: 'a', displayLabel: 'A'),
        comparisonNetlist: const NetlistRef(identifier: 'b', displayLabel: 'B'),
        generatedAt: DateTime.utc(2026, 5, 25, 12),
        elementChanges: const <ElementChange>[
          ElementChange(
            kind: ElementChangeKind.added,
            elementKind: NetlistDiffElementKind.instance,
            elementId: id,
          ),
          ElementChange(
            kind: ElementChangeKind.removed,
            elementKind: NetlistDiffElementKind.net,
            elementId: id,
          ),
        ],
      );
      final restored = NetlistDiff.fromJson(d.toJson());
      expect(restored, equals(d));
    });
  });

  group('NetlistRef', () {
    test('equality is identifier-only', () {
      const a = NetlistRef(identifier: 'foo', displayLabel: 'Foo');
      const b = NetlistRef(identifier: 'foo', displayLabel: 'Different');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('JSON round-trip preserves both fields', () {
      const r = NetlistRef(identifier: 'foo', displayLabel: 'Foo');
      final restored = NetlistRef.fromJson(r.toJson());
      expect(restored, equals(r));
      expect(restored.displayLabel, 'Foo');
    });
  });

  group('NetlistDiffRequest', () {
    test('JSON round-trip with scopeFilter', () {
      const r = NetlistDiffRequest(
        baselineNetlist: NetlistRef(identifier: 'a'),
        comparisonNetlist: NetlistRef(identifier: 'b'),
        scopeFilter: 'top.cpu',
      );
      final restored = NetlistDiffRequest.fromJson(r.toJson());
      expect(restored, equals(r));
    });

    test('copyWith clears scopeFilter explicitly', () {
      const r = NetlistDiffRequest(
        baselineNetlist: NetlistRef(identifier: 'a'),
        comparisonNetlist: NetlistRef(identifier: 'b'),
        scopeFilter: 'top.cpu',
      );
      final r2 = r.copyWith(clearScopeFilter: true);
      expect(r2.scopeFilter, isNull);
    });
  });
}
