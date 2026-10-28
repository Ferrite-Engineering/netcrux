// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Where a test run finds a development build of the native layout engine.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/layout/elk_ffi_library_io.dart';
import 'package:path/path.dart' as p;

/// [path] with symbolic links resolved: the temp directory is behind one on
/// macOS (`/var` is `/private/var`).
String _real(String path) => File(path).resolveSymbolicLinksSync();

void main() {
  late Directory root;
  late Directory previous;

  setUp(() {
    previous = Directory.current;
    root = Directory.systemTemp.createTempSync('elk_ffi_probe_');
    Directory.current = root;
  });

  tearDown(() {
    Directory.current = previous;
    root.deleteSync(recursive: true);
  });

  File build(String relative) =>
      File(p.join(root.path, 'native', 'elk_ffi', 'target', relative))
        ..createSync(recursive: true);

  test('finds nothing when nothing is built', () {
    expect(elkFfiDevBuildPath(), isNull);
  });

  test('finds a plain release build', () {
    final lib = build(p.join('release', elkFfiLibraryFileName()));
    expect(_real(elkFfiDevBuildPath()!), _real(lib.path));
  });

  test('finds a build made with an explicit --target triple', () {
    final lib = build(
      p.join('aarch64-apple-darwin', 'release', elkFfiLibraryFileName()),
    );
    expect(_real(elkFfiDevBuildPath()!), _real(lib.path));
  });

  test('prefers a release build to a debug one, whichever the triple', () {
    build(p.join('debug', elkFfiLibraryFileName()));
    final release = build(
      p.join('x86_64-unknown-linux-gnu', 'release', elkFfiLibraryFileName()),
    );
    expect(
      _real(elkFfiDevBuildPath()!),
      _real(release.path),
    );
  });
}
