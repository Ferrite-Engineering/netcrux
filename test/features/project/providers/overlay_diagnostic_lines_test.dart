// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';

/// The seam a Pro feature adds Diagnostics lines through: none in open core,
/// and the lines it gives parse ahead of the elaboration's own.
void main() {
  test('the open core adds no line', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(overlayDiagnosticLinesProvider), isEmpty);
    expect(container.read(elaborationDiagnosticsProvider), isEmpty);
  });

  test('added lines come first and parse with and without a location', () {
    final container = ProviderContainer(
      overrides: [
        overlayDiagnosticLinesProvider.overrideWithValue(const <String>[
          '/libs/cells.sym:12: Warning: skipped command "arc"',
          'Warning: a library note',
        ]),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(elaborationStderrProvider.notifier)
        .set('Warning: top.v:42: signal foo unused');
    final entries = container.read(elaborationDiagnosticsProvider);
    expect(entries, hasLength(3));
    expect(entries[0].filePath, '/libs/cells.sym');
    expect(entries[0].line, 12);
    expect(entries[0].severity, YosysDiagnosticSeverity.warning);
    expect(entries[0].message, 'skipped command "arc"');
    expect(entries[1].message, 'a library note');
    expect(entries[2].message, contains('signal foo unused'));
  });

  test('added lines show with no elaboration output at all', () {
    final container = ProviderContainer(
      overrides: [
        overlayDiagnosticLinesProvider.overrideWithValue(const <String>[
          'Warning: a library note',
        ]),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(elaborationDiagnosticsProvider), hasLength(1));
  });
}
