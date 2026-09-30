// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/netlist_diff_service.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_request.dart';

void main() {
  group('NoopNetlistDiffService', () {
    test('compare returns the empty diff for any request', () async {
      const service = NoopNetlistDiffService();
      final diff = await service.compare(
        const NetlistDiffRequest(
          baselineNetlist: NetlistRef(identifier: 'a'),
          comparisonNetlist: NetlistRef(identifier: 'b'),
        ),
      );
      expect(diff.elementChanges, isEmpty);
      expect(diff.summary.totalElements, 0);
      expect(diff.isIdentical, isTrue);
    });

    test('diffsInvalidated never emits', () async {
      const service = NoopNetlistDiffService();
      final events = await service.diffsInvalidated
          .take(1)
          .toList(
            // Returns immediately because the stream is empty / closed.
          );
      expect(events, isEmpty);
    });
  });
}
