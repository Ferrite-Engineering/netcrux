// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/source_pane_service.dart';
import 'package:netcrux/domain/models/source_file_content.dart';
import 'package:netcrux/domain/models/source_load_exception.dart';
import 'package:netcrux/domain/models/source_location.dart';
import 'package:netcrux/domain/models/source_token.dart';
import 'package:netcrux/features/source_pane/providers/source_pane_state_provider.dart';
import 'package:netcrux/services/source_pane/source_pane_service_provider.dart';

class _StubService implements SourcePaneService {
  _StubService({this.forwardLookup = const <SourceLocation>[]});

  SourceFileContent? loadResult;
  SourceLoadException? loadError;
  List<SourceLocation> forwardLookup;
  final List<String> loadedPaths = <String>[];
  final StreamController<void> _invalidations =
      StreamController<void>.broadcast();

  @override
  Future<SourceFileContent> loadSource(String filePath) async {
    loadedPaths.add(filePath);
    if (loadError != null) throw loadError!;
    return loadResult ??
        SourceFileContent(
          filePath: filePath,
          lines: const ['a', 'b', 'c'],
          tokens: const <SourceToken>[],
        );
  }

  @override
  Iterable<ElementId> elementsAtSourceLocation(
    String filePath,
    int line, {
    int? column,
  }) => const <ElementId>[];

  @override
  Iterable<SourceLocation> sourceLocationsForElement(ElementId elementId) =>
      forwardLookup;

  @override
  Stream<void> get indexInvalidated => _invalidations.stream;
}

void main() {
  group('SourcePaneStateNotifier', () {
    test('starts in the empty state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(sourcePaneStateProvider),
        equals(SourcePaneState.empty),
      );
    });

    test('setActiveFile populates state via the service', () async {
      final stub = _StubService();
      final container = ProviderContainer(
        overrides: [
          sourcePaneServiceProvider.overrideWithValue(stub),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(sourcePaneStateProvider.notifier)
          .setActiveFile('/proj/a.v', highlightedLines: const {1, 2});

      final state = container.read(sourcePaneStateProvider);
      expect(state.hasContent, isTrue);
      expect(state.currentContent.filePath, equals('/proj/a.v'));
      expect(state.highlightedLines, equals({1, 2}));
      expect(stub.loadedPaths, equals(['/proj/a.v']));
    });

    test(
      'setActiveFile preserves prior content + records error on failure',
      () async {
        final stub = _StubService();
        final container = ProviderContainer(
          overrides: [
            sourcePaneServiceProvider.overrideWithValue(stub),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(sourcePaneStateProvider.notifier)
            .setActiveFile('/proj/a.v');

        // Now arrange the next load to fail.
        stub
          ..loadResult = null
          ..loadError = const SourceLoadException(
            filePath: '/proj/missing.v',
            reason: SourceLoadFailure.notFound,
          );

        await container
            .read(sourcePaneStateProvider.notifier)
            .setActiveFile('/proj/missing.v');

        final state = container.read(sourcePaneStateProvider);
        expect(state.error, isNotNull);
        expect(state.error!.filePath, equals('/proj/missing.v'));
        // Prior content is preserved so the user keeps reading their last
        // successful file.
        expect(state.currentContent.filePath, equals('/proj/a.v'));
      },
    );

    test(
      'setActiveElement loads file for the first location returned',
      () async {
        final stub = _StubService(
          forwardLookup: const [
            SourceLocation(filePath: '/proj/cell.v', line: 12),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            sourcePaneServiceProvider.overrideWithValue(stub),
          ],
        );
        addTearDown(container.dispose);

        const eid = ElementId(kind: ElementKind.instance, path: 'top.cell');
        final result = await container
            .read(sourcePaneStateProvider.notifier)
            .setActiveElement(eid);

        expect(result, isTrue);
        final state = container.read(sourcePaneStateProvider);
        expect(state.currentContent.filePath, equals('/proj/cell.v'));
        expect(state.scrollToLine, equals(12));
        expect(state.highlightedLines, contains(12));
        expect(state.currentElementId, equals(eid));
      },
    );

    test(
      'setActiveElement returns false when element has no source data',
      () async {
        final stub = _StubService();
        final container = ProviderContainer(
          overrides: [
            sourcePaneServiceProvider.overrideWithValue(stub),
          ],
        );
        addTearDown(container.dispose);

        const eid = ElementId(kind: ElementKind.instance, path: 'top.synth');
        final result = await container
            .read(sourcePaneStateProvider.notifier)
            .setActiveElement(eid);
        expect(result, isFalse);
        // Pane stays empty.
        expect(
          container.read(sourcePaneStateProvider),
          equals(SourcePaneState.empty),
        );
      },
    );

    test('clearActiveFile resets to empty', () async {
      final stub = _StubService();
      final container = ProviderContainer(
        overrides: [
          sourcePaneServiceProvider.overrideWithValue(stub),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(sourcePaneStateProvider.notifier)
          .setActiveFile('/proj/a.v');
      expect(container.read(sourcePaneStateProvider).hasContent, isTrue);

      container.read(sourcePaneStateProvider.notifier).clearActiveFile();
      expect(
        container.read(sourcePaneStateProvider),
        equals(SourcePaneState.empty),
      );
    });

    test(
      'setHighlightedLines and acknowledgeScroll work as expected',
      () async {
        final stub = _StubService();
        final container = ProviderContainer(
          overrides: [
            sourcePaneServiceProvider.overrideWithValue(stub),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(sourcePaneStateProvider.notifier)
            .setActiveFile('/proj/a.v');

        container.read(sourcePaneStateProvider.notifier).setHighlightedLines(
          const {3, 4},
        );
        expect(
          container.read(sourcePaneStateProvider).highlightedLines,
          equals({3, 4}),
        );

        container.read(sourcePaneStateProvider.notifier).scrollToLineCenter(7);
        expect(container.read(sourcePaneStateProvider).scrollToLine, equals(7));

        container.read(sourcePaneStateProvider.notifier).acknowledgeScroll();
        expect(container.read(sourcePaneStateProvider).scrollToLine, isNull);
      },
    );
  });
}
