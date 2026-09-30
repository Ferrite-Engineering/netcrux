// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import 'package:path/path.dart' as p;

/// A CXP bind failure must degrade to "cross-probe unavailable",
/// never throw an uncaught SocketException onto the launch path.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('netcrux_cxp_bind_');
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // best effort
    }
  });

  test(
    'binding a taken port degrades to unavailable without throwing',
    () async {
      // Occupy a real port, then ask the CXP server to bind the same one.
      final blocker = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(() async => blocker.close());

      final server = NetcruxCxpServer(
        productVersion: '0.0.0-test',
        manifestDirectory: p.join(tmp.path, 'peers'),
        port: blocker.port,
      );

      // Must complete normally — no SocketException escapes.
      await server.start();

      expect(server.isAvailable, isFalse);
      expect(server.isRunning, isFalse);
      expect(server.boundPort, isNull);
      expect(server.unavailableReason, isNotNull);
      // No manifest was written for a server that never bound.
      final peersDir = Directory(p.join(tmp.path, 'peers'));
      final manifests = peersDir.existsSync()
          ? peersDir.listSync().whereType<File>().where(
              (f) => f.path.endsWith('.json'),
            )
          : const <File>[];
      expect(manifests, isEmpty);

      // stop() on a never-bound server is a clean no-op.
      await server.stop();
    },
  );

  test('a clean bind reports available with no unavailable reason', () async {
    final server = NetcruxCxpServer(
      productVersion: '0.0.0-test',
      manifestDirectory: p.join(tmp.path, 'peers'),
    );
    await server.start();
    addTearDown(server.stop);
    expect(server.isAvailable, isTrue);
    expect(server.unavailableReason, isNull);
  });
}
