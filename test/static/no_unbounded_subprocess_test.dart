// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Static guard — keeps elaboration bounded and killable.
///
/// The Yosys subprocess seam lives in `crux_yosys`, where `Process.start` is
/// raced against the elaboration timeout policy and killed on overrun. No code
/// under `netcrux/lib/services/yosys/` may spawn its own subprocess — doing so
/// would reintroduce an unbounded, unkillable Yosys await (the very gap the
/// timeout policy closes). This guard greps that directory for a raw
/// `Process.run` / `Process.start` and fails CI if one reappears.
///
/// (The static analog of "a decoder shipped without a fixture.")
void main() {
  test('no raw Process spawn under lib/services/yosys/', () {
    final dir = Directory('lib/services/yosys');
    expect(dir.existsSync(), isTrue, reason: 'yosys services dir must exist');

    final offenders = <String>[];
    final spawn = RegExp(r'Process\s*\.\s*(run|start)\s*\(');
    for (final file
        in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.endsWith('.g.dart'))) {
      final source = file.readAsStringSync();
      for (final match in spawn.allMatches(source)) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${p.relative(file.path)}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A raw Process spawn appeared under lib/services/yosys/. The '
          'subprocess seam (with its timeout/kill) belongs in crux_yosys '
          'via the ProcessRunner injected into YosysRunner — do not spawn '
          'Yosys directly here.\n${offenders.join('\n')}',
    );
  });
}
