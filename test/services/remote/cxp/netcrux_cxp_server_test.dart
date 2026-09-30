// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/wait_for.dart';

void main() {
  group('NetcruxCxpServer lifecycle', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('netcrux_cxp_test_');
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // best effort
      }
    });

    test('start binds a port and writes a manifest, stop removes it', () async {
      final manifestDir = p.join(tmp.path, 'crux', 'cxp', 'peers');
      final server = NetcruxCxpServer(
        productVersion: '0.1.0-test',
        manifestDirectory: manifestDir,
      );

      await server.start();
      try {
        expect(server.isRunning, isTrue);
        expect(server.boundPort, isNotNull);
        expect(server.boundPort, isNonZero);
        expect(server.selfIdentity, isNotNull);
        expect(server.selfIdentity!.productName, 'netcrux');
        expect(server.selfIdentity!.productVersion, '0.1.0-test');

        // The manifest file should exist on disk.
        final manifestPath = p.join(
          manifestDir,
          '${server.selfIdentity!.peerId}.json',
        );
        expect(File(manifestPath).existsSync(), isTrue);
      } finally {
        await server.stop();
      }

      // After stop, the file is gone and isRunning is false.
      expect(server.isRunning, isFalse);
      expect(server.boundPort, isNull);
      final entries = Directory(manifestDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(entries, isEmpty);
    });

    test(
      'dial-failure surface is null/empty before start, live after',
      () async {
        final server = NetcruxCxpServer(
          productVersion: '0.0.0',
          manifestDirectory: p.join(tmp.path, 'peers'),
        );

        // Before start the connector does not exist.
        expect(server.dialFailures, isNull);
        expect(server.unreachablePeers, isEmpty);

        await server.start();
        try {
          // A running server exposes the connector's failure stream, and no
          // peer is unreachable because none has been discovered.
          expect(server.dialFailures, isNotNull);
          expect(server.unreachablePeers, isEmpty);
        } finally {
          await server.stop();
        }

        // Teardown returns the surface to the pre-start state.
        expect(server.dialFailures, isNull);
        expect(server.unreachablePeers, isEmpty);
      },
    );

    test('peerId includes pid and timestamp', () async {
      final server = NetcruxCxpServer(
        productVersion: '0.0.0',
        manifestDirectory: p.join(tmp.path, 'peers'),
        clock: () => DateTime.fromMillisecondsSinceEpoch(42),
        pidFactory: () => 1234,
      );
      await server.start();
      try {
        expect(server.selfIdentity!.peerId, 'netcrux-1234-42');
      } finally {
        await server.stop();
      }
    });

    test('accepts a client handshake', () async {
      final server = NetcruxCxpServer(
        productVersion: '0.0.0',
        manifestDirectory: p.join(tmp.path, 'peers'),
      );
      await server.start();
      try {
        final client = LocalCxpClient(
          selfIdentity: const PeerIdentity(
            peerId: 'test-client-1',
            productName: 'test',
            productVersion: '0.0.0',
          ),
        );
        await client.connect(
          host: '127.0.0.1',
          port: server.boundPort!,
          token: cxpProcessAuthToken,
        );
        expect(client.isConnected, isTrue);
        expect(client.remotePeer?.productName, 'netcrux');
        await client.dispose();
      } finally {
        await server.stop();
      }
    });

    test('discovery emits removal when peer manifest is deleted', () async {
      final manifestDir = p.join(tmp.path, 'peers');
      final server = NetcruxCxpServer(
        productVersion: '0.0.0',
        manifestDirectory: manifestDir,
      );
      await server.start();
      try {
        final writer = CxpManifestWriter(manifestDirectory: manifestDir);
        const peer = PeerIdentity(
          peerId: 'fake-peer-removable',
          productName: 'wavecrux',
          productVersion: '0.0.0',
        );
        await writer.write(identity: peer, host: '127.0.0.1', port: 54322);

        var added = false;
        var removed = false;
        final sub = server.discovery!.events.listen((event) {
          if (event.manifest.identity.peerId != peer.peerId) return;
          if (event.added) added = true;
          if (!event.added) removed = true;
        });
        try {
          // The discovery watcher scans on a 2 s interval; bound the
          // polls generously above that.
          await waitFor(
            () => added,
            timeout: const Duration(seconds: 8),
            interval: const Duration(milliseconds: 50),
            reason: 'expected an add event for the peer',
          );

          // Remove the manifest and wait for the remove event.
          await writer.remove();
          await waitFor(
            () => removed,
            timeout: const Duration(seconds: 8),
            interval: const Duration(milliseconds: 50),
            reason: 'expected a remove event after delete',
          );
        } finally {
          await sub.cancel();
        }
      } finally {
        await server.stop();
      }
    });

    test(
      'discovery sees a peer that lands a manifest in the same dir',
      () async {
        final manifestDir = p.join(tmp.path, 'peers');
        // Server A — what we're testing.
        final serverA = NetcruxCxpServer(
          productVersion: '0.0.0',
          manifestDirectory: manifestDir,
        );
        await serverA.start();
        try {
          // Drop a peer manifest into the same directory (simulating a
          // running peer).
          final writer = CxpManifestWriter(manifestDirectory: manifestDir);
          const peerIdentity = PeerIdentity(
            peerId: 'fake-peer-1',
            productName: 'wavecrux',
            productVersion: '0.0.0',
          );
          await writer.write(
            identity: peerIdentity,
            host: '127.0.0.1',
            port: 54322,
          );

          // The discovery watcher should pick the peer up within a few
          // scan intervals (default 2 s; we tolerate up to 4 s here).
          var sawPeer = false;
          final subscription = serverA.discovery!.events.listen((event) {
            if (event.added &&
                event.manifest.identity.peerId == peerIdentity.peerId) {
              sawPeer = true;
            }
          });
          try {
            await waitFor(
              () => sawPeer,
              timeout: const Duration(seconds: 8),
              interval: const Duration(milliseconds: 50),
              reason: 'discovery never emitted an add for the peer manifest',
            );
          } finally {
            await subscription.cancel();
          }
        } finally {
          await serverA.stop();
        }
      },
    );

    test(
      'two servers sharing one manifest directory end up MUTUALLY '
      'CONNECTED via the peer connectors (regression: discovery alone '
      'never opened a socket)',
      () async {
        final a = NetcruxCxpServer(
          productVersion: '0.1.0',
          manifestDirectory: tmp.path,
          pidFactory: () => 1,
        );
        final b = NetcruxCxpServer(
          productVersion: '0.1.0',
          manifestDirectory: tmp.path,
          pidFactory: () => 2,
        );
        await a.start();
        addTearDown(a.stop);
        await b.start();
        addTearDown(b.stop);

        // Pre-fix, discovery surfaced the manifests but no CXP socket was
        // ever opened, so both connectedPeers lists stayed empty forever.
        await waitFor(
          () =>
              (a.server?.connectedPeers ?? []).any(
                (p) => p.peerId == b.selfIdentity?.peerId,
              ) &&
              (b.server?.connectedPeers ?? []).any(
                (p) => p.peerId == a.selfIdentity?.peerId,
              ),
          timeout: const Duration(seconds: 15),
          interval: const Duration(milliseconds: 100),
          reason: 'both servers must see the other CONNECTED',
        );
      },
    );

    test(
      'start publishes its own manifest into the shared dir and keeps it '
      'live across discovery scans (peers must be able to discover NetCrux '
      'back)',
      () async {
        final manifestDir = p.join(tmp.path, 'crux', 'cxp', 'peers');
        final server = NetcruxCxpServer(
          productVersion: '0.1.0-test',
          manifestDirectory: manifestDir,
        );
        await server.start();
        addTearDown(server.stop);

        final manifestPath = p.join(
          manifestDir,
          '${server.selfIdentity!.peerId}.json',
        );
        expect(
          File(manifestPath).existsSync(),
          isTrue,
          reason: 'the manifest must be published on start',
        );

        // Let the discovery watcher run several 2 s scans. A running server
        // must NOT reap its own live manifest — if it did, no peer could
        // discover NetCrux and cross-probe back to it (the regression where
        // the shared dir held every peer EXCEPT netcrux).
        await Future<void>.delayed(const Duration(seconds: 5));
        expect(
          File(manifestPath).existsSync(),
          isTrue,
          reason: 'the running server must keep its own manifest published',
        );
      },
    );

    test(
      'connects to a discovered peer exactly ONCE — repeated discovery / '
      'retry ticks never multiply the outbound connection (socket-leak '
      'regression)',
      () async {
        final manifestDir = p.join(tmp.path, 'peers');
        final peer = _CountingCxpPeer(
          // Non-numeric pid segment so discovery's pid-liveness probe reads
          // "indeterminate" and does NOT reap this synthetic peer's manifest.
          const PeerIdentity(
            peerId: 'wavecrux-fake-99',
            productName: 'wavecrux',
            productVersion: '1.0.0',
          ),
        );
        await peer.start();
        addTearDown(peer.stop);

        // Publish the peer's manifest so NetCrux discovers and dials it.
        final writer = CxpManifestWriter(
          manifestDirectory: manifestDir,
          heartbeatInterval: null,
        );
        await writer.write(
          identity: peer.identity,
          host: '127.0.0.1',
          port: peer.port,
        );

        final server = NetcruxCxpServer(
          productVersion: '0.0.0',
          manifestDirectory: manifestDir,
        );
        await server.start();
        addTearDown(server.stop);

        // The connector dials the peer and completes the handshake once.
        await waitFor(
          () => (server.server?.connectedPeers ?? const <PeerIdentity>[]).any(
            (pr) => pr.peerId == peer.identity.peerId,
          ),
          timeout: const Duration(seconds: 10),
          interval: const Duration(milliseconds: 50),
          reason: 'NetCrux must connect to the discovered peer',
        );
        expect(
          server.server!.connectedPeers.where(
            (pr) => pr.peerId == peer.identity.peerId,
          ),
          hasLength(1),
        );
        expect(
          peer.totalAccepted,
          1,
          reason: 'exactly one outbound socket to the peer',
        );

        // Let more than one connector retry tick (5 s) and several discovery
        // scans (2 s) elapse. A no-dedup / reconnect loop would keep opening
        // fresh sockets; the accepted-socket count must stay pinned at one.
        await Future<void>.delayed(const Duration(seconds: 6));
        expect(
          peer.totalAccepted,
          1,
          reason: 'no reconnect storm: still exactly one accepted socket',
        );
        expect(peer.liveConnections, 1);
        expect(
          server.server!.connectedPeers.where(
            (pr) => pr.peerId == peer.identity.peerId,
          ),
          hasLength(1),
        );
      },
    );
  });
}

/// A minimal CXP peer that only completes the Hello→HelloAck handshake and
/// counts how many inbound sockets it accepts.
///
/// Enough of a real peer for NetCrux's connector to mark it CONNECTED, while
/// exposing [totalAccepted] / [liveConnections] so a test can assert the
/// dialer opened exactly one socket rather than a growing pile.
class _CountingCxpPeer {
  _CountingCxpPeer(this.identity);

  final PeerIdentity identity;
  ServerSocket? _socket;

  /// Total inbound sockets accepted over this peer's lifetime.
  int totalAccepted = 0;
  final Set<Socket> _live = <Socket>{};

  /// Inbound sockets currently open.
  int get liveConnections => _live.length;

  /// The bound port (valid after [start]).
  int get port => _socket!.port;

  Future<void> start() async {
    final s = await ServerSocket.bind('127.0.0.1', 0);
    _socket = s;
    s.listen((sock) {
      totalAccepted++;
      _live.add(sock);
      sock.done.then<void>((_) => _live.remove(sock), onError: (_) {}).ignore();
      sock
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.isEmpty) return;
              final env = CxpEnvelope.fromJson(
                jsonDecode(line) as Map<String, Object?>,
              );
              if (env.kind != CxpMessageKind.hello) return;
              final ack = HelloAck(
                identity: identity,
                inReplyTo: env.messageId,
              );
              sock.write(
                CxpEnvelope(
                  messageId: 'ack-$totalAccepted',
                  from: identity.peerId,
                  kind: ack.kind,
                  payload: ack.toJson(),
                ).encodeLine(),
              );
            },
            onError: (_) {},
            cancelOnError: false,
          );
    });
  }

  Future<void> stop() async {
    for (final sock in _live.toList()) {
      sock.destroy();
    }
    _live.clear();
    await _socket?.close();
    _socket = null;
  }
}
