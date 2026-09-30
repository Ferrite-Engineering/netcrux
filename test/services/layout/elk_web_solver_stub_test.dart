// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/layout/elk_web_solver_stub.dart';

/// Guards the off-web (VM / desktop) resolution of the elkjs solver
/// backend. `elk_layout_service.dart` conditionally imports the browser
/// solver on web and this stub everywhere else; `_solve` routes to the
/// background isolate only because `kElkWebSolverAvailable` is a compile-time
/// `false` here. If someone flips that default, the desktop layout path
/// silently changes — this test is the tripwire.
void main() {
  group('elk web solver (off-web stub)', () {
    test('reports itself unavailable so the isolate path is used', () {
      expect(kElkWebSolverAvailable, isFalse);
    });

    test('solve entry point throws — it must never be reached off-web', () {
      expect(
        () => solveElkOnWeb('{}', () async => ''),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
