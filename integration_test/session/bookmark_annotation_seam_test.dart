// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/session/bookmark_annotation_seam_test.dart
//
// Verification driver for the bookmarks/annotations extension-point seam
// (Open-Core Guide §7.5): boots the real open-core app, seeds a loaded
// design (Yosys-free, via the design-seed helper), and dispatches every
// `BookmarkAnnotationStore` operation against a real cell reference from
// the loaded design. Asserts the `bookmarkAnnotationStoreProvider` seam
// resolves to the open-core `NoopBookmarkAnnotationStore` default and that
// every read/write completes cleanly, producing the documented no-op
// result: writes are silently ignored and `snapshot()` (and the
// `bookmarkAnnotationSnapshotProvider` convenience provider) always
// returns `BookmarkAnnotationSnapshot.empty`.
//
// Inverted counterpart of the Pro overlay's activation test
// (which asserts the seam resolves to the Pro implementation in a Pro
// build): this asserts the open-core no-op default resolves and dispatches
// cleanly with nothing else loaded.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/domain/interfaces/bookmark_annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';

import '../fixtures/design_seed_netlist.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'bookmarks/annotations seam resolves to the open-core no-op store and '
    'dispatches cleanly against a loaded design',
    (tester) async {
      await bootNetcrux(tester, extraOverrides: designSeedBootOverrides());

      final seeded = await seedDesignIntoNewTab(
        tester,
        netlistJson: designSeedNetlistJson,
      );
      final tab = seeded.tab;

      // The top scope lays out asynchronously (elkjs) after the model is
      // injected — wait for it, mirroring
      // `design/seeded_design_journey_test.dart`.
      bool graphHasCell(String id) {
        final graph = tab.read(currentLaidOutGraphProvider).value;
        if (graph == null) return false;
        return graph.graph.cells.any((c) => c.id == id);
      }

      final topLaidOut = await pumpUntil(
        tester,
        () => graphHasCell('u_cpu'),
        timeout: const Duration(seconds: 30),
      );
      expect(topLaidOut, isTrue, reason: 'top scope never laid out');

      // Select a real cell in the seeded design so the bookmark/annotation
      // below targets an element that actually exists on the schematic —
      // mirrors how the Pro dialog openers build the targetId.
      tab
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_cpu'));
      await tester.pump();
      final laidOut = tab.read(currentLaidOutGraphProvider).value;
      expect(laidOut, isNotNull, reason: 'seeded design must be laid out');
      expect(laidOut!.isEmpty, isFalse);
      expect(
        laidOut.graph.cells.any((c) => c.id == 'u_cpu'),
        isTrue,
        reason: 'the bookmark/annotation below targets the u_cpu cell',
      );

      // The seam provider is root-scoped (never re-bound per tab — see
      // `netcrux_tab_overrides.dart`), matching every other extension-point
      // Provider documented in CLAUDE.md.
      final root = rootContainer(tester);
      final store = root.read(bookmarkAnnotationStoreProvider);
      expect(
        store,
        isA<NoopBookmarkAnnotationStore>(),
        reason:
            'open-core resolves bookmarkAnnotationStoreProvider to the '
            'no-op default until a Pro overlay registers a concrete '
            'implementation',
      );
      expect(store.snapshot(), BookmarkAnnotationSnapshot.empty);

      const bookmark = Bookmark(
        id: 'seam-test-bookmark',
        name: 'seam check',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_cpu',
        createdAtMillis: 0,
      );
      const annotation = Annotation(
        id: 'seam-test-annotation',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_cpu',
        body: 'seam check',
        createdAtMillis: 0,
        updatedAtMillis: 0,
      );

      // Every mutating call must complete without throwing and must not
      // change the observable snapshot — the documented no-op contract.
      store.addBookmark(bookmark);
      expect(store.snapshot(), BookmarkAnnotationSnapshot.empty);
      store.updateBookmark(bookmark);
      expect(store.snapshot(), BookmarkAnnotationSnapshot.empty);
      store.addAnnotation(annotation);
      expect(store.snapshot(), BookmarkAnnotationSnapshot.empty);
      store.updateAnnotation(annotation);
      expect(store.snapshot(), BookmarkAnnotationSnapshot.empty);
      store
        ..removeBookmark(bookmark.id)
        ..removeAnnotation(annotation.id)
        ..clear();
      expect(store.snapshot(), BookmarkAnnotationSnapshot.empty);

      // The convenience snapshot provider watches the same seam and must
      // resolve identically.
      expect(
        root.read(bookmarkAnnotationSnapshotProvider),
        BookmarkAnnotationSnapshot.empty,
      );

      expect(tester.takeException(), isNull);
    },
  );
}
