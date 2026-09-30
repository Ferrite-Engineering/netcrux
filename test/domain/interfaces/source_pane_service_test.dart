// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/source_pane_service.dart';
import 'package:netcrux/domain/models/source_load_exception.dart';

void main() {
  group('NoopSourcePaneService', () {
    const service = NoopSourcePaneService();

    test('loadSource throws SourceLoadException.notFound', () async {
      await expectLater(
        () => service.loadSource('/tmp/nope.v'),
        throwsA(
          isA<SourceLoadException>()
              .having((e) => e.filePath, 'filePath', '/tmp/nope.v')
              .having((e) => e.reason, 'reason', SourceLoadFailure.notFound),
        ),
      );
    });

    test('elementsAtSourceLocation returns empty for every input', () {
      expect(service.elementsAtSourceLocation('a.v', 10), isEmpty);
      expect(
        service.elementsAtSourceLocation('a.v', 10, column: 4),
        isEmpty,
      );
    });

    test('sourceLocationsForElement returns empty for every input', () {
      const eid = ElementId(kind: ElementKind.instance, path: 'top.alu');
      expect(service.sourceLocationsForElement(eid), isEmpty);
    });

    test('indexInvalidated is an empty stream', () async {
      final events = <void>[];
      final sub = service.indexInvalidated.listen(events.add);
      // The empty stream completes synchronously; pump the event loop.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events, isEmpty);
    });
  });
}
