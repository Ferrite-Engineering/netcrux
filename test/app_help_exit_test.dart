// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/app.dart';

/// `netcrux --help` must end the process. A desktop runner creates its
/// window and keeps its event loop running after Dart's `main` returns, so a
/// help branch that only returns leaves a blank window and a process that
/// never exits.
void main() {
  for (final flag in const ['--help', '-h']) {
    test('$flag prints usage and exits 0 before the app starts', () async {
      final printed = <String>[];
      int? exitCode;
      await runZoned(
        () => bootstrap(
          args: [flag, 'top.v'],
          exitProcess: (code) => exitCode = code,
        ),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      expect(exitCode, 0);
      expect(printed, hasLength(1));
      expect(printed.single, contains('Usage:'));
    });
  }
}
