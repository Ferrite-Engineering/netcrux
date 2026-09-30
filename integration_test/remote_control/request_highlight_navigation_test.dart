// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/request_highlight_navigation_test.dart
//
// Verification driver for Open-Core Guide §6.3 (request_highlight receive
// → inspector selection / hierarchy nav): boots the real open-core app,
// seeds a loaded design (Yosys-free, via the design-seed helper), connects
// a raw CXP peer directly to the live `NetcruxCxpServer`'s bound port (the
// same raw-socket-as-fake-peer technique
// `test/services/remote/cxp/cxp_inbound_handler_test.dart` uses at the
// unit level — this file drives the same handler through the FULL app,
// i.e. via the real `CxpInboundListener` mounted in `WorkspaceScreen`, not
// a bare `CxpInboundHandler` constructed by hand).
//
// Two request_highlight kinds are exercised end to end:
//  - `ElementKind.instance` → the active tab's `selectedElementProvider`
//    updates and the real `InspectorPanel` widget renders the targeted
//    cell.
//  - `ElementKind.scope` → the active tab's hierarchy navigates into the
//    named instance (`hierarchyTreeProvider.selected`) and the schematic
//    re-lays-out at the new scope, mirroring the navigation assertion in
//    `design/seeded_design_journey_test.dart`.

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/inspector/widgets/inspector_panel.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';

import '../fixtures/design_seed_netlist.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'request_highlight (Guide §6.3): instance selects the cell in the inspector; '
    'scope navigates the hierarchy',
    (tester) async {
      final tmp = Directory.systemTemp.createTempSync(
        'netcrux_request_highlight_it_',
      );
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } on FileSystemException {
          // best effort
        }
      });

      await bootNetcrux(
        tester,
        extraOverrides: <Override>[
          ...designSeedBootOverrides(),
          // Hermetic manifest directory — matches the other CXP
          // integration tests; irrelevant to request_highlight itself
          // (no discovery involved) but keeps every CXP integration test
          // in this directory hermetic by the same convention.
          cxpManifestDirectoryProvider.overrideWith(
            (ref) async => '${tmp.path}/peers',
          ),
        ],
      );

      final seeded = await seedDesignIntoNewTab(
        tester,
        netlistJson: designSeedNetlistJson,
      );
      final tab = seeded.tab;

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

      final root = rootContainer(tester);
      final host = await root.read(cxpServerHostProvider.future);
      expect(host, isNotNull, reason: 'cxpServerEnabled defaults to true');
      expect(
        host!.isAvailable,
        isTrue,
        reason: 'server must be bound for a peer to connect',
      );

      final peer = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: 'request-highlight-it-peer',
          productName: 'test-peer',
          productVersion: '0.0.0-test',
        ),
      );
      addTearDown(peer.dispose);
      await peer.connect(
        host: '127.0.0.1',
        port: host.boundPort!,
        token: cxpProcessAuthToken,
      );

      // ── instance kind → selection + inspector.
      final instanceAckFuture = peer.inbound.firstWhere(
        (m) => m.message is RequestHighlightAck,
      );
      peer.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.instance,
            path: 'top.u_cpu:cell',
          ),
        ),
      );
      final instanceAck =
          (await instanceAckFuture.timeout(const Duration(seconds: 5))).message
              as RequestHighlightAck;
      expect(
        instanceAck.honored,
        isTrue,
        reason: instanceAck.reason ?? 'expected honored=true',
      );

      final selectionUpdated = await pumpUntil(tester, () {
        final selected = tab.read(selectedElementProvider).primary;
        return selected is SelectedElementCell && selected.cellId == 'u_cpu';
      });
      expect(
        selectionUpdated,
        isTrue,
        reason: 'active tab selection never reflected the request_highlight',
      );

      final inspectorShowsCell = await pumpUntil(
        tester,
        () => tester.any(
          find.descendant(
            of: find.byType(InspectorPanel),
            matching: find.text('u_cpu'),
          ),
        ),
      );
      expect(
        inspectorShowsCell,
        isTrue,
        reason: 'inspector never rendered the CXP-highlighted cell',
      );

      // ── scope kind → hierarchy navigation.
      final scopeAckFuture = peer.inbound.firstWhere(
        (m) => m.message is RequestHighlightAck,
      );
      peer.send(
        const RequestHighlight(
          element: ElementId(kind: ElementKind.scope, path: 'top.u_cpu'),
        ),
      );
      final scopeAck =
          (await scopeAckFuture.timeout(const Duration(seconds: 5))).message
              as RequestHighlightAck;
      expect(
        scopeAck.honored,
        isTrue,
        reason: scopeAck.reason ?? 'expected honored=true',
      );

      final hierarchyNavigated = await pumpUntil(
        tester,
        () =>
            tab.read(hierarchyTreeProvider).selected?.path.join('.') == 'u_cpu',
      );
      expect(
        hierarchyNavigated,
        isTrue,
        reason: 'hierarchy selection never navigated into u_cpu',
      );

      // The schematic re-lays-out at the new scope — `u_alu` (a child of
      // `cpu`, not `top`) only appears once the navigation actually took
      // effect, mirroring `design/seeded_design_journey_test.dart`.
      final scopeLaidOut = await pumpUntil(
        tester,
        () => graphHasCell('u_alu'),
        timeout: const Duration(seconds: 30),
      );
      expect(
        scopeLaidOut,
        isTrue,
        reason: 'cpu scope never laid out after the CXP scope navigation',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
