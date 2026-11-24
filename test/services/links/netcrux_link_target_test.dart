// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/links/netcrux_link_target.dart';
import 'package:path/path.dart' as p;

/// The file a link names is judged before it is opened: the CXP receive
/// floor, a design format both as named and once symbolic links resolve, and
/// a regular file that exists. These run over real files in a temporary
/// directory, on every host CI runs.

late Directory _dir;

String _write(String name, [String body = 'module top; endmodule\n']) {
  final path = p.join(_dir.path, name);
  File(path).writeAsStringSync(body);
  return path;
}

NetCruxLinkTargetRefusal? _refusal(String path, {bool? windows}) =>
    switch (vetNetCruxLinkTarget(path, windows: windows)) {
      NetCruxLinkTargetRefused(:final refusal) => refusal,
      NetCruxLinkTargetAccepted() => null,
    };

void main() {
  setUp(() {
    _dir = Directory(
      Directory.systemTemp
          .createTempSync('netcrux_link_target_')
          .resolveSymbolicLinksSync(),
    );
  });
  tearDown(() => _dir.deleteSync(recursive: true));

  test('every design format a link may open is accepted, in any case', () {
    for (final name in [
      'top.v',
      'top.sv',
      'top.vh',
      'top.svh',
      'top.vhd',
      'top.vhdl',
      'top.json',
      'UPPER.V',
    ]) {
      final path = _write(name);
      final result = vetNetCruxLinkTarget(path);
      expect(result, isA<NetCruxLinkTargetAccepted>(), reason: name);
      expect((result as NetCruxLinkTargetAccepted).path, path);
    }
  });

  test('files that carry commands or name further files are refused', () {
    for (final name in [
      'design.netcrux-project',
      'view.netcrux',
      'all.netcrux-workspace',
      'top.crux-project',
      'sources.f',
      'synth.ys',
      'run.tcl',
      'run.sh',
      'top.v.gz',
      'top',
    ]) {
      expect(
        _refusal(_write(name)),
        NetCruxLinkTargetRefusal.notADesign,
        reason: name,
      );
    }
  });

  test('a relative path is refused before the filesystem is asked', () {
    expect(_refusal('top.v'), NetCruxLinkTargetRefusal.pathRefused);
    expect(_refusal('rtl/top.v'), NetCruxLinkTargetRefusal.pathRefused);
    expect(_refusal(''), NetCruxLinkTargetRefusal.pathRefused);
  });

  test('a missing file or a directory is not found', () {
    expect(
      _refusal(p.join(_dir.path, 'gone.v')),
      NetCruxLinkTargetRefusal.fileNotFound,
    );
    final folder = Directory(p.join(_dir.path, 'rtl.v'))..createSync();
    expect(_refusal(folder.path), NetCruxLinkTargetRefusal.fileNotFound);
  });

  test(
    'a design name that links to another kind of file is refused',
    () {
      final secret = _write('id_ed25519', 'not a design');
      final disguised = p.join(_dir.path, 'top.v');
      Link(disguised).createSync(secret);
      expect(_refusal(disguised), NetCruxLinkTargetRefusal.notADesign);
    },
    skip: Platform.isWindows ? 'symbolic links need privileges' : false,
  );

  test(
    'a link to a design resolves to the file it points at',
    () {
      final real = _write('real.sv');
      final alias = p.join(_dir.path, 'alias.v');
      Link(alias).createSync(real);
      final result = vetNetCruxLinkTarget(alias);
      expect(result, isA<NetCruxLinkTargetAccepted>());
      expect((result as NetCruxLinkTargetAccepted).path, real);
    },
    skip: Platform.isWindows ? 'symbolic links need privileges' : false,
  );

  test('Windows device names and streams are refused by spelling', () {
    expect(isWindowsDeviceOrStreamForTest(r'C:\work\NUL.v'), isTrue);
    expect(isWindowsDeviceOrStreamForTest(r'C:\work\com1.sv'), isTrue);
    expect(isWindowsDeviceOrStreamForTest(r'C:\work\top.v:hidden'), isTrue);
    expect(isWindowsDeviceOrStreamForTest(r'C:\work\top.v'), isFalse);
    expect(isWindowsDeviceOrStreamForTest(r'C:\work\console.v'), isFalse);
    final device = p.join(_dir.path, 'nul.v');
    expect(
      _refusal(device, windows: true),
      NetCruxLinkTargetRefusal.pathRefused,
    );
  });

  group('opened before', () {
    test('a file in a tab or a recent list counts, by identity', () {
      final path = _write('top.v');
      final spelled = p.join(_dir.path, '.', 'top.v');
      expect(
        wasOpenedBefore(
          path,
          openTabPaths: [null, spelled],
          recentPaths: const [],
        ),
        isTrue,
      );
      expect(
        wasOpenedBefore(path, openTabPaths: const [], recentPaths: [spelled]),
        isTrue,
      );
    });

    test('anything else does not', () {
      final path = _write('top.v');
      final other = _write('other.v');
      expect(
        wasOpenedBefore(
          path,
          openTabPaths: [other, null, ''],
          recentPaths: [other],
        ),
        isFalse,
      );
    });
  });
}
