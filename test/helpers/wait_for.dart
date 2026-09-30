// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Shared bounded condition-poll helpers for VM unit tests.
//
// The unit-test twin of the integration harness's `pumpUntil`
// (`integration_test/helpers/app_driver.dart`): a fixed
// `Future<void>.delayed(...)` is a raced guess — too short and the test
// flakes under load, too long and every run pays the full wait. A bounded
// poll returns the instant the real observable (response frame arrived,
// provider value changed, discovery event fired) is true, and fails
// loudly with [reason] at the timeout instead of letting a downstream
// assertion fail mysteriously.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Polls [condition] every [interval] until it returns true, failing the
/// test with [reason] if [timeout] elapses first.
///
/// [condition] may be synchronous or async. Prefer polling the ACTUAL
/// observable the code under test mutates (a received-messages list, a
/// server's `connectedPeers`, an event flag) over any proxy.
Future<void> waitFor(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 10),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (await Future<bool>.sync(condition)) return;
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'waitFor: condition not met within $timeout'
        '${reason == null ? '' : ' — $reason'}',
      );
    }
    await Future<void>.delayed(interval);
  }
}

/// Best-effort recursive delete of a systemTemp directory that background
/// work (a debounced workspace autosave renaming into it) may still be
/// writing to, racing the delete with "Directory not empty". Retries
/// briefly, then gives up — a leaked systemTemp dir is harmless (the OS
/// reaps it).
Future<void> bestEffortDeleteTempDir(Directory dir) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}
