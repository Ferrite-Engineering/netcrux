// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';

import '../../../helpers/wait_for.dart';
import 'cxp_test_barrier.dart';

/// End-to-end conformance test against `NetcruxCxpServer`'s underlying
/// `LocalCxpServer`, matching the crux_cxp `test/conformance/` suite.
///
/// Exercises the protocol surface a Crux peer is expected to honour:
/// hello/helloAck handshake, subscribe + broadcast routing, targeted
/// sendTo, ErrorResponse on unknown kinds, clean shutdown, presence
/// events on connect/disconnect. The conformance suite for the v1
/// protocol lives in crux_cxp/test/conformance/server_client_test.dart;
/// this file re-runs the same shape of assertions against the
/// NetcruxCxpServer wrapper to prove it passes the suite when wired
/// through the manifest writer + discovery layers.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('netcrux_cxp_conf_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // best effort
    }
  });

  Future<({NetcruxCxpServer server, LocalCxpClient client})> bootPair() async {
    final server = NetcruxCxpServer(
      productVersion: '0.0.0-test',
      manifestDirectory: '${tmp.path}/peers',
    );
    await server.start();
    final client = LocalCxpClient(
      selfIdentity: const PeerIdentity(
        peerId: 'conformance-client-1',
        productName: 'conformance',
        productVersion: '0.0.0-test',
      ),
    );
    await client.connect(
      host: '127.0.0.1',
      port: server.boundPort!,
      token: cxpProcessAuthToken,
    );
    return (server: server, client: client);
  }

  Future<void> tearDownPair(
    NetcruxCxpServer server,
    LocalCxpClient client,
  ) async {
    await client.dispose();
    await server.stop();
  }

  test(
    'handshake completes and remote peer carries NetCrux identity',
    () async {
      final pair = await bootPair();
      expect(pair.client.isConnected, isTrue);
      expect(pair.client.remotePeer?.productName, 'netcrux');
      expect(pair.client.remotePeer?.productVersion, '0.0.0-test');
      await tearDownPair(pair.server, pair.client);
    },
  );

  test('subscribe + broadcast routes only to subscribers', () async {
    final pair = await bootPair();
    pair.client.send(
      const Subscribe(
        subscriptions: <CxpSubscription>[
          CxpSubscription(messageKind: CxpMessageKind.notifySelection),
        ],
      ),
    );
    // FIFO round-trip proves the Subscribe is registered server-side.
    await cxpRoundTripBarrier(pair.client);
    final received = pair.client.inbound.first;
    pair.server.server!.broadcast(
      const NotifySelection(
        elements: <ElementId>[
          ElementId(kind: ElementKind.instance, path: 'top.cpu:cell'),
        ],
      ),
    );
    final inbound = await received.timeout(const Duration(seconds: 2));
    expect(inbound.message, isA<NotifySelection>());
    await tearDownPair(pair.server, pair.client);
  });

  test('unknown kind yields ErrorResponse(unknown_kind)', () async {
    final pair = await bootPair();
    final errFuture = pair.client.inbound.firstWhere(
      (m) => m.message is ErrorResponse,
    );
    pair.client.send(_UnknownKind());
    final inbound = await errFuture.timeout(const Duration(seconds: 2));
    final err = inbound.message as ErrorResponse;
    expect(err.code, CxpErrorCode.unknownKind);
    await tearDownPair(pair.server, pair.client);
  });

  test('clean disconnect removes peer from server', () async {
    final pair = await bootPair();
    await waitFor(
      () => pair.server.server!.connectedPeers.length == 1,
      reason: 'server never registered the connected peer',
    );
    await pair.client.disconnect();
    await waitFor(
      () => pair.server.server!.connectedPeers.isEmpty,
      reason: 'server never dropped the disconnected peer',
    );
    await pair.client.dispose();
    await pair.server.stop();
  });

  test('targeted sendTo routes to the named peer only', () async {
    final server = NetcruxCxpServer(
      productVersion: '0.0.0-test',
      manifestDirectory: '${tmp.path}/peers',
    );
    await server.start();
    final a = LocalCxpClient(
      selfIdentity: const PeerIdentity(
        peerId: 'conformance-a',
        productName: 'conformance',
        productVersion: '0.0.0-test',
      ),
    );
    final b = LocalCxpClient(
      selfIdentity: const PeerIdentity(
        peerId: 'conformance-b',
        productName: 'conformance',
        productVersion: '0.0.0-test',
      ),
    );
    await a.connect(
      host: '127.0.0.1',
      port: server.boundPort!,
      token: cxpProcessAuthToken,
    );
    await b.connect(
      host: '127.0.0.1',
      port: server.boundPort!,
      token: cxpProcessAuthToken,
    );
    a.send(
      const Subscribe(
        subscriptions: <CxpSubscription>[
          CxpSubscription(messageKind: CxpMessageKind.notifySelection),
        ],
      ),
    );
    b.send(
      const Subscribe(
        subscriptions: <CxpSubscription>[
          CxpSubscription(messageKind: CxpMessageKind.notifySelection),
        ],
      ),
    );
    // FIFO round-trips prove both Subscribes are registered server-side.
    await cxpRoundTripBarrier(a);
    await cxpRoundTripBarrier(b);
    final aFuture = a.inbound.first;
    final bReceived = <CxpClientInbound>[];
    final bSub = b.inbound.listen(bReceived.add);
    final delivered = server.server!.sendTo(
      'conformance-a',
      const NotifySelection(
        elements: <ElementId>[
          ElementId(kind: ElementKind.instance, path: 't'),
        ],
      ),
    );
    expect(delivered, isTrue);
    await aFuture.timeout(const Duration(seconds: 2));
    // Negative assertion made deterministic: a sentinel targeted at b is
    // written to b's socket AFTER any (mis-routed) a-payload would have
    // been, so once the sentinel arrives, b's stream provably carried no
    // earlier message (same-socket FIFO).
    final sentinelDelivered = server.server!.sendTo(
      'conformance-b',
      const NotifySelection(
        elements: <ElementId>[
          ElementId(kind: ElementKind.instance, path: 'sentinel'),
        ],
      ),
    );
    expect(sentinelDelivered, isTrue);
    await waitFor(
      () => bReceived.isNotEmpty,
      reason: 'b never received the sentinel',
    );
    await bSub.cancel();
    expect(bReceived, hasLength(1));
    final sentinel = bReceived.single.message as NotifySelection;
    expect(sentinel.elements.single.path, 'sentinel');
    await a.dispose();
    await b.dispose();
    await server.stop();
  });
}

class _UnknownKind extends CxpMessage {
  @override
  String get kind => 'netcrux_test_unknown_kind';
  @override
  Map<String, Object?> toJson() => const <String, Object?>{};
}
