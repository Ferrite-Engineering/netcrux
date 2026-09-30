// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/remote/cxp/cxp_inbound_handler.dart';
import 'package:netcrux/services/remote/cxp/cxp_outbound_emitter_controller.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/telemetry_test_overrides.dart';
import '../../../helpers/wait_for.dart';

/// Coverage for connector-link traffic merging. A `CxpPeerConnector` used
/// to prove presence only — the remote peer's server saw us connected, but
/// every frame arriving on our OWN connector-owned client socket (a peer
/// replying to us, or gossiping notify_selection to us) was discarded
/// because nothing listened to that socket's inbound stream. NetCrux's
/// production wiring (`NetcruxCxpServer.start`) now constructs its
/// `CxpPeerConnector` with `server: server`, which merges connector-link
/// traffic into `LocalCxpServer.inbound` and auto-subscribes the link —
/// exactly the seam these tests exercise. Both tests use only real
/// `CxpPeerConnector` / `LocalCxpServer` production wiring — no
/// hand-rolled `LocalCxpClient` playing the role of a peer.
NetlistModel _model() {
  Cell cell(String name, String type) => Cell(
    name: name,
    type: type,
    parameters: const {},
    attributes: const {},
    portDirections: const {},
    connections: const {},
  );
  final top = Module(
    name: 'top',
    attributes: const <String, String>{'top': '1'},
    ports: const {},
    cells: <String, Cell>{'u_cpu': cell('u_cpu', 'cpu')},
    nets: const {},
  );
  const cpu = Module(
    name: 'cpu',
    attributes: <String, String>{},
    ports: <String, Port>{},
    cells: <String, Cell>{},
    nets: <String, Net>{},
  );
  return NetlistModel(
    creator: 'test',
    modules: <String, Module>{'top': top, 'cpu': cpu},
  );
}

/// Starts a "remote peer" (playing e.g. WaveCrux) with a manifest
/// published into [manifestDir], so NetCrux's own connector (started
/// separately) discovers and dials it. Returns the peer's server plus
/// the inbound frames it observes — the same `server.inbound`
/// subscription a real product's request handler uses.
///
/// When [symmetric] is true (the real-world default — every Crux
/// product runs a connector alongside its server) the peer ALSO runs
/// its own `CxpDiscovery` + `CxpPeerConnector(server: server)` dialing
/// back into whatever else publishes a manifest into [manifestDir].
/// That second link is what lets the remote peer's own auto-subscribe
/// register on the OTHER side's server — needed for tests that assert a
/// broadcast FROM that other side reaches this peer.
Future<
  ({
    LocalCxpServer server,
    CxpManifestWriter writer,
    CxpDiscovery? discovery,
    CxpPeerConnector? connector,
    List<InboundCxpMessage> inbound,
  })
>
_startRemotePeer(
  String manifestDir,
  PeerIdentity identity, {
  bool symmetric = false,
}) async {
  final server = LocalCxpServer(selfIdentity: identity);
  await server.start();
  final writer = CxpManifestWriter(
    manifestDirectory: manifestDir,
    heartbeatInterval: const Duration(milliseconds: 100),
  );
  await writer.write(
    identity: identity,
    host: '127.0.0.1',
    port: server.boundPort!,
  );
  final inbound = <InboundCxpMessage>[];
  server.inbound.listen(inbound.add);

  CxpDiscovery? discovery;
  CxpPeerConnector? connector;
  if (symmetric) {
    discovery = CxpDiscovery(
      manifestDirectory: manifestDir,
      scanInterval: const Duration(milliseconds: 50),
    );
    connector = CxpPeerConnector(
      selfIdentity: identity,
      discovery: discovery,
      server: server,
      retryInterval: const Duration(milliseconds: 100),
    );
    await discovery.start();
    connector.start();
  }

  return (
    server: server,
    writer: writer,
    discovery: discovery,
    connector: connector,
    inbound: inbound,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('CxpPeerConnector production wiring', () {
    test(
      'a request arriving purely over our own connector link (not a '
      "socket the remote dialed into us) reaches NetCrux's inbound "
      'handler and the ack returns over the same link',
      () async {
        final tmp = Directory.systemTemp.createTempSync('cxp_link_req_');
        addTearDown(() async {
          try {
            tmp.deleteSync(recursive: true);
          } on FileSystemException {
            // best effort
          }
        });

        final manifestDir = p.join(tmp.path, 'peers');
        final netcrux = NetcruxCxpServer(
          productVersion: '0.0.0-test',
          manifestDirectory: manifestDir,
        );
        await netcrux.start();
        addTearDown(netcrux.stop);

        const remoteIdentity = PeerIdentity(
          peerId: 'wavecrux-link-req',
          productName: 'wavecrux',
          productVersion: '0.0.0-test',
        );
        final remote = await _startRemotePeer(manifestDir, remoteIdentity);
        addTearDown(remote.server.stop);
        addTearDown(remote.writer.remove);

        final rootContainer = ProviderContainer(
          overrides: netcruxTelemetryTestOverrides(),
        );
        final tabContainer = ProviderContainer(parent: rootContainer);
        tabContainer.read(hierarchyTreeProvider.notifier).setModel(_model());
        addTearDown(tabContainer.dispose);
        addTearDown(rootContainer.dispose);

        final handler = CxpInboundHandler(
          server: netcrux.server!,
          rootContainer: rootContainer,
          activeTabContainerLookup: () => tabContainer,
        );
        addTearDown(handler.dispose);

        // NetCrux's own connector (constructed inside NetcruxCxpServer.start
        // with server: netcrux.server) must discover and dial the remote
        // peer — proving the link exists before the remote uses it as a
        // reply/delivery path.
        await waitFor(
          () => remote.server.connectedPeers.any(
            (peer) => peer.peerId == netcrux.selfIdentity?.peerId,
          ),
          reason: "the remote peer's server never saw NetCrux connect",
        );

        // The remote sends a RequestHighlight to NetCrux over the socket
        // it accepted (i.e. the one NetCrux's connector opened). Without
        // the connector's inbound merge (server: server), this frame
        // would land only on the connector's own client's `.inbound`
        // stream, which CxpInboundHandler never subscribes to.
        final delivered = remote.server.sendTo(
          netcrux.selfIdentity!.peerId,
          const RequestHighlight(
            element: ElementId(
              kind: ElementKind.instance,
              path: 'top.u_cpu:cell',
            ),
          ),
        );
        expect(delivered, isTrue);

        await waitFor(
          () => remote.inbound.any((m) => m.message is RequestHighlightAck),
          reason: "NetCrux's ack never reached the remote peer",
        );
        final ack =
            remote.inbound
                    .firstWhere((m) => m.message is RequestHighlightAck)
                    .message
                as RequestHighlightAck;
        expect(ack.honored, isTrue);

        // The handler actually acted on the request — the cell got
        // selected in the active tab, proving the frame reached
        // CxpInboundHandler and not merely the connector's socket.
        final selection = tabContainer.read(selectedElementProvider);
        expect(selection.primary, isA<SelectedElementCell>());
        expect(
          (selection.primary as SelectedElementCell).cellId,
          'u_cpu',
        );
      },
    );

    test(
      'notify_selection broadcast by the outbound emitter reaches a peer '
      "connected purely via the connector's auto-subscribe — no manual "
      'Subscribe call anywhere in this test',
      () async {
        final tmp = Directory.systemTemp.createTempSync('cxp_link_notify_');
        addTearDown(() async {
          try {
            tmp.deleteSync(recursive: true);
          } on FileSystemException {
            // best effort
          }
        });

        final manifestDir = p.join(tmp.path, 'peers');
        final netcrux = NetcruxCxpServer(
          productVersion: '0.0.0-test',
          manifestDirectory: manifestDir,
        );
        await netcrux.start();
        addTearDown(netcrux.stop);

        const remoteIdentity = PeerIdentity(
          peerId: 'wavecrux-link-notify',
          productName: 'wavecrux',
          productVersion: '0.0.0-test',
        );
        // Symmetric: the remote also runs its own connector dialing back
        // into NetCrux (exactly what a second real Crux product does),
        // which is what lets ITS auto-subscribe register on NETCRUX's
        // server — the precondition for NetCrux's own broadcast to reach
        // it.
        final remote = await _startRemotePeer(
          manifestDir,
          remoteIdentity,
          symmetric: true,
        );
        addTearDown(() async {
          await remote.connector?.stop();
          await remote.discovery?.stop();
        });
        addTearDown(remote.server.stop);
        addTearDown(remote.writer.remove);

        // Wait for the remote's auto-subscribe to register on NetCrux's
        // server — the connector sends Subscribe immediately after its
        // handshake completes, with no product-level wiring on either
        // side. debugSubscriptionsOf is keyed by the SUBSCRIBING peer's
        // ID, observed on the server that RECEIVES the broadcast.
        await waitFor(
          () =>
              (netcrux.server?.debugSubscriptionsOf(remoteIdentity.peerId) ??
                      const <CxpSubscription>[])
                  .isNotEmpty,
          reason: "the remote's auto-subscribe never registered on NetCrux",
        );

        final container = ProviderContainer(
          overrides: [
            ...netcruxTelemetryTestOverrides(),
            cxpServerHostProvider.overrideWith(
              () => _StaticCxpServerHost(netcrux),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(cxpServerHostProvider.future);
        container.read(hierarchyTreeProvider.notifier).setModel(_model());

        final controller = CxpOutboundEmitterController(container);
        addTearDown(controller.dispose);

        container
            .read(selectedElementProvider.notifier)
            .select(const SelectedElement.cell(cellId: 'u_cpu'));

        await waitFor(
          () => remote.inbound.any((m) => m.message is NotifySelection),
          reason: 'notify_selection never reached the auto-subscribed peer',
        );
        final notify =
            remote.inbound
                    .firstWhere((m) => m.message is NotifySelection)
                    .message
                as NotifySelection;
        // Outbound cross-probe now carries the clean dot-joined instance name.
        expect(notify.elements.single.path, 'top.u_cpu');
      },
    );
  });
}

class _StaticCxpServerHost extends CxpServerHost {
  _StaticCxpServerHost(this._server);

  final NetcruxCxpServer _server;

  @override
  Future<NetcruxCxpServer?> build() async => _server;
}
