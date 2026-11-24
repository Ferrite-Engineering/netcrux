// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The headless binary's version against the manifest it restates: every
// document names it, and `pubspec.yaml` is where the release sets it.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/headless/cli_version.dart';

void main() {
  test('the version is the pubspec version without its build number', () {
    final line = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('version: '));
    final version = line.substring('version: '.length).split('+').first;
    expect(kNetCruxCliVersion, version);
  });
}
