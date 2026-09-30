// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/engines/bundled_binary_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  group('BundledBinaryResolver', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('netcrux_bbr_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    String currentPlatformDir() {
      if (Platform.isLinux) return 'linux-x86_64';
      if (Platform.isMacOS) return 'macos-universal';
      if (Platform.isWindows) return 'windows-x86_64';
      throw StateError('Unsupported test host');
    }

    String exeName(String engineId) =>
        Platform.isWindows ? '$engineId.exe' : engineId;

    test('returns null when no override and no env var', () {
      final resolver = BundledBinaryResolver(overrideRoot: tempDir.path);
      // The temp dir exists but is empty — no per-platform subdir, so
      // even though overrideRoot is set, the resolver returns null.
      expect(resolver.resolve('yosys'), isNull);
    });

    test('resolves yosys when present in override root', () async {
      final platformDir = currentPlatformDir();
      final binDir = Directory(p.join(tempDir.path, platformDir));
      await binDir.create(recursive: true);
      final yosys = File(p.join(binDir.path, exeName('yosys')));
      await yosys.writeAsString('#!/bin/sh\necho fake yosys\n');
      final resolver = BundledBinaryResolver(overrideRoot: tempDir.path);
      expect(resolver.resolve('yosys'), yosys.path);
    });

    test('resolves ghdl when present in override root', () async {
      final platformDir = currentPlatformDir();
      final binDir = Directory(p.join(tempDir.path, platformDir));
      await binDir.create(recursive: true);
      final ghdl = File(p.join(binDir.path, exeName('ghdl')));
      await ghdl.writeAsString('#!/bin/sh\necho fake ghdl\n');
      final resolver = BundledBinaryResolver(overrideRoot: tempDir.path);
      expect(resolver.resolve('ghdl'), ghdl.path);
    });

    test('returns null when file does not exist for engine', () async {
      final platformDir = currentPlatformDir();
      await Directory(
        p.join(tempDir.path, platformDir),
      ).create(recursive: true);
      final resolver = BundledBinaryResolver(overrideRoot: tempDir.path);
      // Directory exists but yosys binary is not in it.
      expect(resolver.resolve('yosys'), isNull);
    });

    test(
      'env var name is the documented NETCRUX_BUNDLED_BIN_DIR constant',
      () {
        // Guard against accidental rename — the CI helper and the
        // resolver have to agree on the same env var name.
        expect(BundledBinaryResolver.envVarName, 'NETCRUX_BUNDLED_BIN_DIR');
      },
    );
  });
}
