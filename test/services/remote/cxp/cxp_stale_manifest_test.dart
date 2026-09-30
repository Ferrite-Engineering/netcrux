// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A stale discovery manifest (a peer that died without cleanup) is
/// pruned by the discovery watcher rather than blocking the UI with a connect
/// attempt to a dead peer. Exercises the `CxpDiscovery` the NetCrux CXP server
/// runs.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('netcrux_cxp_stale_');
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // best effort
    }
  });

  void writeManifest(String peerId, DateTime startedAt) {
    final manifest = CxpPeerManifest(
      identity: PeerIdentity(
        peerId: peerId,
        productName: 'netcrux',
        productVersion: '0.0.0-test',
      ),
      host: '127.0.0.1',
      port: 54321,
      startedAt: startedAt,
      manifestPath: '',
    );
    File(
      p.join(tmp.path, '$peerId.json'),
    ).writeAsStringSync(jsonEncode(manifest.toJson()));
  }

  test(
    'a manifest older than the stale threshold is pruned from the view',
    () async {
      final now = DateTime.now().toUtc();
      writeManifest('dead-peer', now.subtract(const Duration(hours: 1)));
      writeManifest('live-peer', now);

      final discovery = CxpDiscovery(
        manifestDirectory: tmp.path,
        staleThreshold: const Duration(seconds: 30),
      );
      await discovery.start();
      addTearDown(discovery.stop);

      // The initial scan drops the stale peer and keeps the live one.
      final peerIds = discovery.peers.map((m) => m.identity.peerId).toSet();
      expect(
        peerIds,
        isNot(contains('dead-peer')),
        reason: 'a >1h-old manifest must be pruned (stale peer)',
      );
      expect(
        peerIds,
        contains('live-peer'),
        reason: 'a fresh manifest must survive',
      );

      // Pruning is view-only for a manifest this process does not own. A
      // discovery that deletes other processes' files turns a laptop wake
      // into a spurious full cross-product disconnect: every product's
      // scan runs before any product's heartbeat, so all four delete each
      // other's manifests and every connector tears down its link.
      expect(
        File(p.join(tmp.path, 'dead-peer.json')).existsSync(),
        isTrue,
        reason: "another process's manifest must be left on disk",
      );
    },
  );

  test('a stale manifest this process owns is deleted from disk', () async {
    final now = DateTime.now().toUtc();
    writeManifest('me', now.subtract(const Duration(hours: 1)));

    final discovery = CxpDiscovery(
      manifestDirectory: tmp.path,
      selfPeerId: 'me',
      staleThreshold: const Duration(seconds: 30),
    );
    await discovery.start();
    addTearDown(discovery.stop);

    // We own this file, so cleaning up our own leftovers is safe.
    expect(File(p.join(tmp.path, 'me.json')).existsSync(), isFalse);
    expect(discovery.peers, isEmpty);
  });

  test('a fresh-only directory prunes nothing', () async {
    writeManifest('live-peer', DateTime.now().toUtc());
    final discovery = CxpDiscovery(
      manifestDirectory: tmp.path,
      staleThreshold: const Duration(seconds: 30),
    );
    await discovery.start();
    addTearDown(discovery.stop);
    expect(File(p.join(tmp.path, 'live-peer.json')).existsSync(), isTrue);
  });
}
