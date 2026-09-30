// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_summary.dart';

void main() {
  group('NetlistDiffSummary', () {
    const id = ElementId(kind: ElementKind.instance, path: 'top.x');

    test('counts add up per (kind × elementKind)', () {
      final summary = NetlistDiffSummary.from(const <ElementChange>[
        ElementChange(
          kind: ElementChangeKind.added,
          elementKind: NetlistDiffElementKind.instance,
          elementId: id,
        ),
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
        ElementChange(
          kind: ElementChangeKind.modified,
          elementKind: NetlistDiffElementKind.port,
          elementId: id,
        ),
        ElementChange(
          kind: ElementChangeKind.unchanged,
          elementKind: NetlistDiffElementKind.instance,
          elementId: id,
        ),
      ]);
      expect(summary.added(NetlistDiffElementKind.instance), 2);
      expect(summary.unchanged(NetlistDiffElementKind.instance), 1);
      expect(summary.removed(NetlistDiffElementKind.net), 1);
      expect(summary.modified(NetlistDiffElementKind.port), 1);
      expect(summary.totalAdded, 2);
      expect(summary.totalRemoved, 1);
      expect(summary.totalModified, 1);
      expect(summary.totalUnchanged, 1);
      expect(summary.totalChanged, 4);
      expect(summary.totalElements, 5);
    });

    test('modificationIntensity is 0.0 for an empty diff', () {
      final s = NetlistDiffSummary.from(const <ElementChange>[]);
      expect(s.modificationIntensity, 0.0);
    });

    test('modificationIntensity is 0.0 for an all-unchanged diff', () {
      final s = NetlistDiffSummary.from(const <ElementChange>[
        ElementChange(
          kind: ElementChangeKind.unchanged,
          elementKind: NetlistDiffElementKind.instance,
          elementId: id,
        ),
      ]);
      expect(s.modificationIntensity, 0.0);
    });

    test('modificationIntensity is 1.0 when nothing is unchanged', () {
      final s = NetlistDiffSummary.from(const <ElementChange>[
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
      ]);
      expect(s.modificationIntensity, 1.0);
    });

    test('JSON round-trip preserves counts', () {
      final original = NetlistDiffSummary.from(const <ElementChange>[
        ElementChange(
          kind: ElementChangeKind.added,
          elementKind: NetlistDiffElementKind.instance,
          elementId: id,
        ),
        ElementChange(
          kind: ElementChangeKind.modified,
          elementKind: NetlistDiffElementKind.port,
          elementId: id,
        ),
      ]);
      final restored = NetlistDiffSummary.fromJson(original.toJson());
      expect(restored, equals(original));
    });
  });
}
