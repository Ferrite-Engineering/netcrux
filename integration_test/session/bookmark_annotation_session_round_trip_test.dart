// integration_test/session/bookmark_annotation_session_round_trip_test.dart
//
// Verification driver for bookmarks + annotations (Verification Guide §7.5): seed a design into
// the active tab (Yosys-free, via the design-seed helper), add a bookmark and
// an annotation through the real `InSessionBookmarkAnnotationStore` (the same
// store the Bookmarks and Annotations panels call into), persist a `.netcrux`
// session, clear the store (simulating the app closing the session), then
// reload the session through the real `SessionController.openByPath` (the
// same method `File > Open Session…` invokes) and assert the bookmark and
// annotation survive the round trip.
//
// `SessionController.saveAs()` cannot be driven directly in a test: it calls
// the static `FilePicker.saveFile`, which has no injection seam. This journey
// instead mirrors the accepted pattern in
// `test/services/session/session_controller_test.dart`: write the
// `NetcruxSession` JSON directly (the shape `SessionController._snapshot()`
// produces, sourced from the live per-tab providers) and drive the real
// `openByPath` load path, which is where `store.clear()` +
// `addBookmark` / `addAnnotation` lives.
//
// `bookmarkAnnotationStoreProvider` is re-bound per tab (in
// `netcruxTabOverridesFactory`, alongside its state notifier): each tab's
// bookmarks and annotations belong to that tab's design, and a `.netcrux`
// session is one tab's view. So the store is read, and the session saved and
// loaded, through the seeded tab's container, the way `SessionController` is
// bound by the workspace dispatcher.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/domain/models/session/netcrux_session.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/workspace/widgets/project_tab_content.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';
import 'package:netcrux/services/session/session_controller.dart';

import '../fixtures/design_seed_netlist.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'bookmarks + annotations round-trip through a .netcrux session',
    (tester) async {
      await bootNetcrux(tester, extraOverrides: designSeedBootOverrides());

      final seeded = await seedDesignIntoNewTab(
        tester,
        netlistJson: designSeedNetlistJson,
      );
      final tab = seeded.tab;

      // Add a bookmark + annotation through the REAL production store —
      // the same object the bookmarks panel calls into.
      final store = tab.read(bookmarkAnnotationStoreProvider);
      const bookmark = Bookmark(
        id: 'bm-1',
        name: 'CPU entry point',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_cpu',
        createdAtMillis: 1000,
        note: 'Come back here after the reset review.',
      );
      const annotation = Annotation(
        id: 'an-1',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_cpu',
        body: 'This is the top-level CPU instance.',
        createdAtMillis: 1000,
        updatedAtMillis: 1000,
        author: 'martin',
      );
      store
        ..addBookmark(bookmark)
        ..addAnnotation(annotation);

      final beforeSave = store.snapshot();
      expect(beforeSave.bookmarks, [bookmark]);
      expect(beforeSave.annotations, [annotation]);

      // Build the SessionController the exact way the workspace-screen
      // dispatcher's "Save Session As…" / "Open Session…" actions do —
      // bound to the active tab's container (see
      // `workspace_action_dispatcher.dart`'s `_saveSession` /
      // `_openSession`).
      final element = tester.element(find.byType(ProjectTabContent));
      final controller = SessionController(
        container: tab,
        messenger: ScaffoldMessenger.of(element),
        l10n: L10N.of(element),
      );

      // "Save": persist the session JSON with the real bookmark /
      // annotation snapshot and the tab's real source-file list, so
      // the subsequent load's idempotent `setSourceFiles` call
      // (CurrentProject.setProject no-ops on an equal project) can't
      // re-trigger elaboration and disturb the seeded model.
      final sourceFiles = tab.read(currentProjectProvider).sourceFiles;
      final session = NetcruxSession(
        version: NetcruxSession.currentVersion,
        sourceFilePaths: sourceFiles,
        topModule: seeded.model.topModule?.name ?? '',
        scopePath: const <String>[],
        zoom: 1,
        panX: 0,
        panY: 0,
        selectionJson: null,
        overlayMode: null,
        expandedScopeKeys: const <String>[],
        bookmarks: beforeSave.bookmarks,
        annotations: beforeSave.annotations,
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'netcrux-bookmark-session-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final path = '${tempDir.path}/session.${NetcruxSession.fileExtension}';
      await File(
        path,
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert(session.toJson()),
      );

      // Simulate closing the session: clear the live store.
      store.clear();
      expect(store.snapshot().isEmpty, isTrue);

      // "Reopen": drive the REAL production load path.
      await controller.openByPath(path);
      // Flush the post-frame callback `_apply` schedules for the
      // bookmark/annotation restore.
      await tester.pump();

      final afterReopen = tab.read(bookmarkAnnotationStoreProvider).snapshot();
      expect(
        afterReopen.bookmarks,
        [bookmark],
        reason: 'the bookmark must survive the .netcrux session round trip',
      );
      expect(
        afterReopen.annotations,
        [annotation],
        reason: 'the annotation must survive the .netcrux session round trip',
      );

      // The panel-facing watch provider reflects the same restored
      // state (proves the auto-rebuild wiring, not just the store).
      final watched = tab.read(bookmarkAnnotationSnapshotProvider);
      expect(watched.bookmarks, [bookmark]);
      expect(watched.annotations, [annotation]);

      expect(tester.takeException(), isNull);
    },
  );
}
