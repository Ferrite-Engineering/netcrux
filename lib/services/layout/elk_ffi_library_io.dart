// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Resolution of the native layout engine library, `elk_ffi`, the C ABI over
// the vendored elkrs port of the Eclipse Layout Kernel (`native/elk_ffi`).
// Every desktop build compiles, bundles and signs it; the layout worker opens
// it through [openElkFfiLibrary] rather than guessing at a file name.

import 'dart:ffi' as ffi;
import 'dart:io';

/// Opens a library by name or path. Injectable so tests can observe or stub
/// the `dlopen` without touching the filesystem probe.
typedef ElkFfiLibraryOpener = ffi.DynamicLibrary Function(String path);

ffi.DynamicLibrary _dlopen(String path) => ffi.DynamicLibrary.open(path);

/// The platform file name of the layout engine library, e.g.
/// `libelk_ffi.dylib`. Throws [UnsupportedError] where no native build
/// exists (the web edition runs elkjs in the browser instead).
String elkFfiLibraryFileName() {
  if (Platform.isLinux || Platform.isAndroid) return 'libelk_ffi.so';
  if (Platform.isMacOS) return 'libelk_ffi.dylib';
  if (Platform.isWindows) return 'elk_ffi.dll';
  throw UnsupportedError(
    'elk_ffi: no native layout library for ${Platform.operatingSystem}',
  );
}

/// Resolves and opens the layout engine library.
///
/// The lookup order is:
///
/// 1. **Bare name**, the production path. In a `flutter run` or packaged
///    desktop build the library lives in the `.app`'s Frameworks/ directory
///    (macOS), next to the executable (Windows), or in the bundle's `lib/`
///    subtree (Linux); the dynamic loader finds it through the bundle's
///    rpath without an explicit path.
/// 2. **`native/elk_ffi/target/{release,debug}/...`** under a probed root,
///    the `flutter test` path. The test process is a plain Dart VM with no
///    bundle, so the bare name throws; falling back to the path `cargo
///    build` produces lets the tests find the library on a developer machine
///    or CI runner without any extra setup. Probed roots are
///    [Directory.current] (the open-core checkout) and
///    `{Directory.current}/netcrux` (the Pro overlay, which consumes this
///    repo as a `./netcrux` submodule and runs `flutter test` one level up).
///
/// If every candidate misses, the bare name is retried so the caller sees
/// the platform's own error message rather than a generic "not found".
ffi.DynamicLibrary openElkFfiLibrary({ElkFfiLibraryOpener opener = _dlopen}) {
  final fileName = elkFfiLibraryFileName();
  try {
    return opener(fileName);
  } on Object {
    // Fall through to the development-build probe below.
  }
  final path = elkFfiDevBuildPath();
  if (path != null) return opener(path);
  return opener(fileName);
}

/// The first existing `cargo build` output of the layout engine library under
/// the probed checkout roots (see [openElkFfiLibrary]), or `null` when none
/// has been built. Release is preferred over debug.
String? elkFfiDevBuildPath() {
  final fileName = elkFfiLibraryFileName();
  final cwd = Directory.current.path;
  const profiles = <String>['release', 'debug'];
  for (final root in <String>[cwd, '$cwd/netcrux']) {
    for (final profile in profiles) {
      final candidate = '$root/native/elk_ffi/target/$profile/$fileName';
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return null;
}
