// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/source_pane_service.dart';
import 'package:netcrux/domain/models/source_file_content.dart';
import 'package:netcrux/domain/models/source_location.dart';
import 'package:netcrux/services/source_pane/source_pane_service_provider.dart';

class _FakeSourcePaneService implements SourcePaneService {
  _FakeSourcePaneService();

  @override
  Future<SourceFileContent> loadSource(String filePath) async {
    return SourceFileContent(
      filePath: filePath,
      lines: const ['hello'],
      tokens: const [],
    );
  }

  @override
  Iterable<ElementId> elementsAtSourceLocation(
    String filePath,
    int line, {
    int? column,
  }) => const [ElementId(kind: ElementKind.instance, path: 'top.fake')];

  @override
  Iterable<SourceLocation> sourceLocationsForElement(ElementId elementId) =>
      const [SourceLocation(filePath: 'fake.v', line: 1)];

  @override
  Stream<void> get indexInvalidated => const Stream<void>.empty();
}

void main() {
  group('sourcePaneServiceProvider', () {
    test('default resolves to NoopSourcePaneService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final svc = container.read(sourcePaneServiceProvider);
      expect(svc, isA<NoopSourcePaneService>());
    });

    test('Pro-style override replaces the default', () async {
      final container = ProviderContainer(
        overrides: [
          sourcePaneServiceProvider.overrideWithValue(_FakeSourcePaneService()),
        ],
      );
      addTearDown(container.dispose);
      final svc = container.read(sourcePaneServiceProvider);
      expect(svc, isA<_FakeSourcePaneService>());
      final content = await svc.loadSource('a.v');
      expect(content.filePath, equals('a.v'));
      expect(content.lines, equals(['hello']));
    });
  });
}
