// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/layout/elk_ffi_library_io.dart';

/// Whether a test that needs the native layout engine may proceed.
///
/// Without a `cargo build --release` of `native/elk_ffi`, the test is
/// skipped on a developer machine, where a Dart-only change should not
/// demand a Rust toolchain, and **fails under `CI=true`**, where a missing
/// build would otherwise turn the parity gate and the native tests into
/// silent skips. Returns `false` after marking the skip.
bool requireElkFfiLibrary() {
  if (elkFfiDevBuildPath() != null) return true;
  const message =
      'native/elk_ffi is not built; run `cargo build --release` in '
      'native/elk_ffi';
  if (Platform.environment['CI'] == 'true') {
    fail('$message (a CI runner must build it before flutter test)');
  }
  markTestSkipped(message);
  return false;
}
