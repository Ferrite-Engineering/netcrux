// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/session/session_export_round_trip_test.dart
//
// Verification driver for Open-Core Guide §4.1.3 (`.netcrux` session
// export / reopen round-trip): drives the live viewer state (hierarchy
// scope, selection, camera) on a seeded design, saves a real `.netcrux`
// session through `SessionController.saveToPath` (the picker-free
// counterpart to the File → Save Session As… dialog flow — see that
// method's doc comment), mutates the live state away from the saved
// values, then reopens the session file through `SessionController
// .openByPath` (the same method the picker-driven File → Open Session…
// flow calls once it has resolved a path) and asserts the scope /
// selection / camera state came back exactly as saved.
//
// Mirrors `workspace/restore_round_trip_test.dart` and
// `workspace/named_workspace_test.dart`'s shape: drive real mutations,
// force a real on-disk write, then re-read through the same production
// code path a cold reopen would use.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/workspace/widgets/project_tab_content.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/session_controller.dart';

import '../fixtures/design_seed_netlist.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'export a session with loaded scope/selection/camera state, reopen '
    'it, and the state comes back identically (Guide §4.1.3)',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('netcrux_session_rt_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final sessionPath = '${dir.path}/roundtrip.netcrux';

      // A seed the pipeline can load again. Reopening a session loads the
      // session's design afresh — its source list is the session's — so a
      // design injected after a failed elaboration would reopen onto that
      // failure, and nothing of the view could be restored onto it.
      await bootNetcrux(
        tester,
        extraOverrides: netlistDocumentSeedBootOverrides(designSeedNetlistJson),
      );

      final seeded = await seedNetlistDocumentIntoNewTab(tester);
      final tab = seeded.tab;

      // Wait for the top scope to lay out (elkjs is async), mirroring
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

      // Navigate into the u_cpu scope and select the ALU cell inside it —
      // real hierarchy state that a session must preserve across reload.
      tab.read(hierarchyTreeProvider.notifier).selectByPath(<String>['u_cpu']);
      final scopedLaidOut = await pumpUntil(
        tester,
        () => graphHasCell('u_alu'),
        timeout: const Duration(seconds: 30),
      );
      expect(scopedLaidOut, isTrue, reason: 'u_cpu scope never laid out');
      expect(
        tab.read(hierarchyTreeProvider).selected?.path,
        <String>['u_cpu'],
      );

      tab
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_alu'));
      await tester.pump();

      // Distinct, non-default camera state.
      tab.read(viewportTransformProvider.notifier).setZoom(2.5);
      tab.read(viewportTransformProvider.notifier).pan(const Offset(37, -19));
      final savedTransform = tab.read(viewportTransformProvider);
      expect(savedTransform.zoom, 2.5);

      // A live BuildContext under the seeded tab's mounted content, so the
      // controller has a real ScaffoldMessenger + L10N to read through —
      // the same shape `workspace_action_dispatcher._saveSession` /
      // `._openSession` build it in.
      final context = tester.element(find.byType(ProjectTabContent).first);
      final controller = SessionController(
        container: tab,
        messenger: ScaffoldMessenger.of(context),
        l10n: L10N.of(context),
      );

      // Export — picker-free direct-path write (see SessionController
      // .saveToPath's doc comment for why this bypasses the OS dialog).
      await controller.saveToPath(sessionPath);
      expect(
        File(sessionPath).existsSync(),
        isTrue,
        reason: 'saveToPath must write the session file',
      );

      // Mutate the live state away from what was saved, so the reopen
      // assertions below can't pass by coincidence.
      tab.read(hierarchyTreeProvider.notifier).selectByPath(<String>[]);
      tab.read(selectedElementProvider.notifier).replace(Selection.empty);
      tab.read(viewportTransformProvider.notifier).reset();
      expect(tab.read(hierarchyTreeProvider).selected?.path, isEmpty);
      expect(tab.read(selectedElementProvider).isEmpty, isTrue);
      expect(tab.read(viewportTransformProvider).zoom, 1.0);

      // Let the root scope's layout land first. The reopen hands its camera
      // to the canvas for the next layout of the saved scope, and a root
      // layout still in flight would spend that request on the wrong scope.
      final rootLaidOut = await pumpUntil(
        tester,
        () => graphHasCell('u_cpu') && !graphHasCell('u_alu'),
        timeout: const Duration(seconds: 30),
      );
      expect(rootLaidOut, isTrue, reason: 'root scope never laid out again');

      // Reopen — the same method the picker-driven "Open Session…" flow
      // calls once FilePicker resolves a path. It loads the session's design
      // and completes once the view has been applied to it: scope, expanded
      // rows and selection at once, and the camera handed to the canvas to
      // reinstate when the saved scope's layout lands, in place of the fit a
      // new layout otherwise gets.
      await controller.openByPath(sessionPath);

      expect(
        identical(tab.read(loadedNetlistProvider).value, seeded.model),
        isFalse,
        reason: 'the reopen loaded the design afresh, as a cold open would',
      );
      expect(
        tab.read(hierarchyTreeProvider).selected?.path,
        <String>['u_cpu'],
        reason: 'reopening the session must restore the navigated scope',
      );
      expect(
        tab.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'u_alu'),
        reason: 'reopening the session must restore the cell selection',
      );

      bool cameraRestored() {
        final transform = tab.read(viewportTransformProvider);
        return transform.zoom == savedTransform.zoom &&
            transform.offset == savedTransform.offset;
      }

      final landed = await pumpUntil(
        tester,
        () => graphHasCell('u_alu') && cameraRestored(),
        timeout: const Duration(seconds: 30),
      );
      final restoredTransform = tab.read(viewportTransformProvider);
      expect(
        landed,
        isTrue,
        reason: 'the saved scope laid out with its camera',
      );
      expect(
        restoredTransform.zoom,
        savedTransform.zoom,
        reason: 'reopening the session must restore the saved zoom',
      );
      expect(
        restoredTransform.offset,
        savedTransform.offset,
        reason: 'reopening the session must restore the saved pan offset',
      );
      expect(
        tab.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'u_alu'),
        reason: 'the restored scope laying out keeps the restored selection',
      );

      // Drain trailing async work so teardown sees a settled tree.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    },
  );
}
