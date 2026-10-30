// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/scope_layout_gate_provider.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';
import 'package:netcrux/features/viewer/providers/held_back_selection_cone_provider.dart';
import 'package:netcrux/features/viewer/providers/layout_approval_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/services/analysis_selection_probe.dart';
import 'package:netcrux/features/viewer/services/cone_view_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/cxp_runtime_rig.dart';
import '../../../helpers/held_back_tab_rig.dart';

const _u5 = SelectedElement.cell(cellId: 'u5');

/// A held-back tab: 30 cells against a limit of 10, with the watcher alive
/// the way the tab content keeps it.
Future<HeldBackTabRig> _heldBack() async {
  final rig = await HeldBackTabRig.open(cells: 30, limit: 10);
  addTearDown(rig.dispose);
  rig.showDesign();
  rig.tab.listen(heldBackSelectionConeProvider, (_, _) {});
  expect(rig.tab.read(scopeLayoutGateProvider).deferred, isTrue);
  return rig;
}

/// What the canvas settles on showing.
Future<({int cells, ConeViewExtent? cone})> _settle(
  ProviderContainer tab,
) async {
  final sub = tab.listen(currentLaidOutGraphProvider, (_, _) {});
  addTearDown(sub.close);
  final laidOut = await tab.read(currentLaidOutGraphProvider.future);
  return (cells: laidOut.graph.cells.length, cone: laidOut.cone);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('a selection in a scope held back for its size', () {
    test('opens the cone of a cell, fan-in at the default depth', () async {
      final rig = await _heldBack();
      rig.tab.read(selectedElementProvider.notifier).select(_u5);

      final cone = rig.tab.read(coneViewProvider)!;
      expect(cone.root, _u5);
      expect(cone.direction, ConeViewDirection.fanIn);
      expect(cone.depth, kDefaultConeViewDepth);
      expect(cone.scope, rig.tab.read(hierarchyTreeProvider).selected);
      expect(rig.tab.read(scopeLayoutGateProvider).deferred, isFalse);

      final shown = await _settle(rig.tab);
      expect(shown.cone?.request, cone);
      expect(shown.cone?.scopeCellCount, 30);
      // u5 and the two cells before it; the 30-cell scope is never laid out.
      expect(shown.cells, 3);
      expect(rig.service.wholeScopeCalls, 0);
    });

    test('opens the cone of a pin, a wire and a boundary port', () async {
      for (final element in <SelectedElement>[
        const SelectedElement.port(
          cellId: 'u5',
          portId: 'u5.Y',
          portName: 'Y',
        ),
        const SelectedElement.wire(edgeId: 'e:5', netId: 8),
        const SelectedElement.boundaryPort(
          portId: 'port:in0',
          portName: 'in0',
        ),
      ]) {
        final rig = await _heldBack();
        rig.tab.read(selectedElementProvider.notifier).select(element);
        expect(rig.tab.read(coneViewProvider)?.root, element);
        expect(rig.tab.read(scopeLayoutGateProvider).deferred, isFalse);
        final shown = await _settle(rig.tab);
        expect(shown.cone, isNotNull);
        expect(rig.service.wholeScopeCalls, 0);
      }
    });

    test('a cleared selection opens nothing', () async {
      final rig = await _heldBack();
      rig.tab.read(selectedElementProvider.notifier)
        ..select(_u5)
        ..clear();
      // The cone the pick opened stays, as it always does when the selection
      // is cleared; clearing alone opens none.
      expect(rig.tab.read(coneViewProvider)?.root, _u5);

      final other = await _heldBack();
      other.tab.read(selectedElementProvider.notifier).clear();
      expect(other.tab.read(coneViewProvider), isNull);
      expect(other.tab.read(scopeLayoutGateProvider).deferred, isTrue);
    });

    test('Show Whole Scope returns to the held-back view, not a layout, '
        'and does not reopen the cone', () async {
      final rig = await _heldBack();
      rig.tab.read(selectedElementProvider.notifier).select(_u5);
      await _settle(rig.tab);
      ConeViewController(rig.tab.read).exit();

      expect(rig.tab.read(coneViewProvider), isNull);
      expect(rig.tab.read(scopeLayoutGateProvider).deferred, isTrue);
      // Leaving the cone asked for no reveal, which would read as a new pick.
      expect(rig.tab.read(revealRequestProvider), isNull);
      expect(rig.tab.read(selectedElementProvider).primary, _u5);
      final shown = await _settle(rig.tab);
      expect(shown.cells, 0);
      expect(rig.service.wholeScopeCalls, 0);
    });

    test('picking the cell that is already selected opens the cone again '
        'after Show Whole Scope', () async {
      final rig = await _heldBack();
      final selection = rig.tab.read(selectedElementProvider.notifier)
        ..select(_u5);
      ConeViewController(rig.tab.read).exit();
      expect(rig.tab.read(coneViewProvider), isNull);

      // A second pick of u5 changes no selection; the reveal every
      // jump-to-element route makes after selecting is what carries it.
      selection.select(_u5);
      expect(rig.tab.read(coneViewProvider), isNull);
      rig.tab.read(revealRequestProvider.notifier).request('u5');
      expect(rig.tab.read(coneViewProvider)?.root, _u5);
    });

    test('a pick inside the cone on show is left to the canvas', () async {
      final rig = await _heldBack();
      // The scope is no longer held back once the cone is on show, so a
      // click on another cell of the cone is the canvas' business, not this
      // watcher's: the cone keeps its root.
      rig.tab.read(selectedElementProvider.notifier)
        ..select(_u5)
        ..select(const SelectedElement.cell(cellId: 'u4'));
      expect(rig.tab.read(coneViewProvider)?.root, _u5);
    });

    test('an approved scope lays out whole and takes a selection as '
        'before', () async {
      final rig = await _heldBack();
      final scope = rig.tab.read(hierarchyTreeProvider).selected!;
      rig.tab.read(layoutApprovalProvider.notifier).approve(scope);
      rig.tab.read(selectedElementProvider.notifier).select(_u5);
      expect(rig.tab.read(coneViewProvider), isNull);
      final shown = await _settle(rig.tab);
      expect(shown.cells, 30);
      expect(rig.service.wholeScopeCalls, 1);
    });
  });

  group('a selection in a scope under the limit', () {
    test('opens no cone', () async {
      final rig = await HeldBackTabRig.open(cells: 30, limit: 100);
      addTearDown(rig.dispose);
      rig.showDesign();
      rig.tab.listen(heldBackSelectionConeProvider, (_, _) {});
      expect(rig.tab.read(scopeLayoutGateProvider).deferred, isFalse);

      rig.tab.read(selectedElementProvider.notifier).select(_u5);
      rig.tab.read(revealRequestProvider.notifier).request('u5');
      expect(rig.tab.read(coneViewProvider), isNull);
      final shown = await _settle(rig.tab);
      expect(shown.cells, 30);
      expect(shown.cone, isNull);
    });
  });

  group('the cross-probe routes', () {
    test('an analysis jump to a cell opens its cone', () async {
      final rig = await _heldBack();
      expect(AnalysisSelectionProbe(rig.tab).revealCellIn('flat', 'u7'), true);
      expect(
        rig.tab.read(coneViewProvider)?.root,
        const SelectedElement.cell(cellId: 'u7'),
      );
      expect(rig.tab.read(scopeLayoutGateProvider).deferred, isFalse);
    });

    test('an analysis jump to a net opens the cone of its wire', () async {
      final rig = await _heldBack();
      expect(AnalysisSelectionProbe(rig.tab).revealNetIn('flat', 'n7'), true);
      final root = rig.tab.read(coneViewProvider)?.root;
      expect(root, isA<SelectedElementWire>());
      expect(rig.tab.read(scopeLayoutGateProvider).deferred, isFalse);
      final shown = await _settle(rig.tab);
      expect(shown.cone, isNotNull);
      expect(rig.service.wholeScopeCalls, 0);
    });

    test('an analysis jump to a boundary port opens its cone', () async {
      final rig = await _heldBack();
      expect(AnalysisSelectionProbe(rig.tab).selectPortIn('flat', 'in0'), true);
      expect(
        rig.tab.read(coneViewProvider)?.root,
        const SelectedElement.boundaryPort(
          portId: 'port:in0',
          portName: 'in0',
        ),
      );
    });

    test('a request_highlight from a peer opens the cone of the cell it '
        'names', () async {
      final rig = await _heldBack();
      final tmp = Directory.systemTemp.createTempSync('held_back_cxp_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final server = CxpRuntimeRig(manifestDirectory: '${tmp.path}/peers');
      await server.start();
      addTearDown(server.stop);
      final client = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: 'wavecrux-held-back-test',
          productName: 'wavecrux',
          productVersion: '0.0.0-test',
        ),
      );
      await client.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: cxpProcessAuthToken,
      );
      addTearDown(client.dispose);
      final handler = AttachedCxpHandler(
        server: server,
        rootContainer: rig.root,
        activeTabContainerLookup: () => rig.tab,
      );
      addTearDown(handler.dispose);

      final ack = client.inbound.firstWhere(
        (m) => m.message is RequestHighlightAck,
      );
      client.send(
        const RequestHighlight(
          element: ElementId(kind: ElementKind.instance, path: 'flat.u9:cell'),
        ),
      );
      final inbound = await ack.timeout(const Duration(seconds: 10));
      final reply = inbound.message as RequestHighlightAck;
      expect(reply.honored, isTrue, reason: '${reply.reason}');

      expect(
        rig.tab.read(coneViewProvider)?.root,
        const SelectedElement.cell(cellId: 'u9'),
      );
      expect(rig.tab.read(scopeLayoutGateProvider).deferred, isFalse);
    });
  });
}
