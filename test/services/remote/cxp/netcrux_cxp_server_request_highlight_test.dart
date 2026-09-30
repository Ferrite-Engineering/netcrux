// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/wait_for.dart';

/// Regression coverage for the ack-correlation path
/// ([NetcruxCxpServer.requestHighlight]) that the explicit cross-probe send
/// (panel per-peer + schematic menu) relies on. A live NetCrux→WaveCrux send
/// appeared dead: the concern was that the acked `request_highlight` either
/// hung forever waiting for a `RequestHighlightAck` or never correlated one
/// from a waveform peer.
///
/// These tests drive the real socket path against a fake WaveCrux-style peer
/// (a [LocalCxpClient] that connects and replies) to prove the wrapper:
///   * completes promptly with the peer's ack when the peer honors it (no
///     hang), and
///   * times out to `(delivered: true, ack: null)` — a surfaceable failure,
///     not a hang — when the peer never acks.
void main() {
  group('NetcruxCxpServer.requestHighlight ack correlation', () {
    late Directory tmp;
    late NetcruxCxpServer server;
    late LocalCxpClient peer;

    const peerId = 'wavecrux-fake-1';
    const request = RequestHighlight(
      element: ElementId(kind: ElementKind.net, path: 'top.state'),
    );

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('netcrux_reqhl_test_');
      server = NetcruxCxpServer(
        productVersion: '0.0.0-test',
        manifestDirectory: p.join(tmp.path, 'peers'),
      );
      await server.start();

      // A fake WaveCrux peer that dials NetCrux (an inbound connection on
      // NetCrux's side) — the same shape as a real waveform peer's connector
      // link, whose Hello identity is what NetCrux's `sendTo(peerId, …)` and
      // ack correlation key off.
      peer = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: peerId,
          productName: 'wavecrux',
          productVersion: '0.0.1',
          capabilities: <String>{'request_highlight'},
        ),
      );
      await peer.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: cxpProcessAuthToken,
      );
      // The wrapper sends via `server.sendTo(peerId, …)`, which resolves the
      // peer from the server's accepted connections — wait for the handshake
      // to register the peer before dispatching.
      await waitFor(
        () => server.server!.connectedPeers.any((it) => it.peerId == peerId),
        reason: 'peer handshake must register before the directed send',
      );
    });

    tearDown(() async {
      try {
        await peer.disconnect();
      } on Object {
        // best effort
      }
      await server.stop();
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // best effort
      }
    });

    test('a peer that acks honored:true completes promptly with the ack '
        '(no hang)', () async {
      // The peer replies to any inbound request_highlight with an honored ack,
      // the way WaveCrux's server wrapper does.
      peer.inbound.listen((inbound) {
        if (inbound.message is RequestHighlight) {
          peer.send(
            RequestHighlightAck(
              inReplyTo: inbound.envelope.messageId,
              honored: true,
            ),
          );
        }
      });

      final result = await server
          .requestHighlight(peerId, request)
          .timeout(const Duration(seconds: 3));

      expect(result.delivered, isTrue);
      expect(result.ack, isNotNull);
      expect(result.ack!.honored, isTrue);
    });

    test('a peer that acks honored:false surfaces the decline (delivered, '
        'ack.honored == false)', () async {
      peer.inbound.listen((inbound) {
        if (inbound.message is RequestHighlight) {
          peer.send(
            RequestHighlightAck(
              inReplyTo: inbound.envelope.messageId,
              honored: false,
              reason: 'element not found in current design',
            ),
          );
        }
      });

      final result = await server
          .requestHighlight(peerId, request)
          .timeout(const Duration(seconds: 3));

      expect(result.delivered, isTrue);
      expect(result.ack, isNotNull);
      expect(result.ack!.honored, isFalse);
      expect(result.ack!.reason, contains('not found'));
    });

    test('a peer that never acks times out to a surfaceable failure — not a '
        'hang', () async {
      // The peer receives the request but deliberately never replies.
      final result = await server
          .requestHighlight(
            peerId,
            request,
            timeout: const Duration(milliseconds: 300),
          )
          // A generous outer bound: if the wrapper hangs past its own timeout
          // this outer timeout throws and fails the test loudly.
          .timeout(const Duration(seconds: 3));

      expect(result.delivered, isTrue);
      expect(result.ack, isNull);
    });
  });
}
