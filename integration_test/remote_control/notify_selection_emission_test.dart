// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/notify_selection_emission_test.dart
//
// Verification driver for Open-Core Guide §6.2 (notify_selection emission
// on canvas selection): boots the real open-core app, seeds a loaded
// design (Yosys-free, via the design-seed helper), connects a raw CXP peer
// directly to the live `NetcruxCxpServer`'s bound port (the same
// raw-socket-as-fake-peer technique
// `test/services/remote/cxp/cxp_outbound_emitter_controller_test.dart`
// uses at the unit level), subscribes it to `notify_selection`, selects an
// element, and asserts the peer receives a `NotifySelection` with the
// correct canonical `ElementId` and metadata.
//
// Selection is driven through `selectedElementProvider` — the exact
// provider `SchematicGestureHandler._onTapUp` writes to when the user taps
// a cell on the schematic canvas (`lib/features/viewer/widgets/
// schematic_gesture_handler.dart`; the canvas itself is a single
// `CustomPainter`-backed `LeafRenderObjectWidget` with no per-cell `Key`s
// to target with `tester.tap`, so every seam test in this suite drives
// selection through the provider the gesture handler and the hierarchy
// panel both write to). `CxpOutboundEmitterController` — mounted per the
// active tab via `CxpOutboundEmitter` in `workspace_screen.dart` — listens
// on exactly this provider regardless of where the selection originated,
// so this exercises the real production emission pipeline end to end.

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';

import '../fixtures/design_seed_netlist.dart';
import '../helpers/app_driver.dart';
import '../helpers/cxp_test_barrier.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'canvas selection emits notify_selection to a subscribed CXP peer '
    '(Guide §6.2)',
    (tester) async {
      final tmp = Directory.systemTemp.createTempSync(
        'netcrux_notify_selection_it_',
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
          // Hermetic manifest directory — never touch the real
          // suite-shared discovery location, and never discover a real
          // running suite product on the dev host mid-test.
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
          peerId: 'notify-selection-it-peer',
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
      peer.send(
        const Subscribe(
          subscriptions: <CxpSubscription>[
            CxpSubscription(messageKind: CxpMessageKind.notifySelection),
          ],
        ),
      );
      // FIFO round-trip proves the Subscribe is registered server-side
      // before the test body triggers a selection below.
      await cxpRoundTripBarrier(peer);

      final notifyFuture = peer.inbound
          .firstWhere((m) => m.message is NotifySelection)
          .timeout(const Duration(seconds: 5));

      tab
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_cpu'));

      final inbound = await notifyFuture;
      final notify = inbound.message as NotifySelection;
      expect(notify.elements, hasLength(1));
      expect(notify.elements.first.kind, ElementKind.instance);
      // Clean dot-joined path, NOT `buildElementPath`'s `top.u_cpu:cell`:
      // a receiver leaf-matches by splitting on `.`, so an in-band marker
      // never resolves. `kind: instance` carries the disambiguation
      // instead. `buildElementPath` still emits the marked form for
      // "Copy Path" and local resolution.
      expect(notify.elements.first.path, 'top.u_cpu');
      expect(notify.displayName, 'u_cpu');
      expect(notify.metadata['netcrux.scope_path'], 'top');

      expect(tester.takeException(), isNull);
    },
  );
}
