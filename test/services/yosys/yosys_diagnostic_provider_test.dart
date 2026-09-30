// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/yosys_diagnostic_provider.dart';

void main() {
  test('yosysDiagnosticParserProvider returns a parser by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(yosysDiagnosticParserProvider),
      isA<YosysDiagnosticParser>(),
    );
  });

  test('yosysErrorDiagnosticProvider parses stderr into diagnostics', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const stderr = '''
foo.v:3: ERROR: bad
Warning: deprecated
''';
    final diagnostics = container.read(yosysErrorDiagnosticProvider(stderr));
    expect(diagnostics, hasLength(2));
    expect(diagnostics.first.severity, YosysDiagnosticSeverity.error);
    expect(diagnostics.first.filePath, 'foo.v');
    expect(diagnostics.first.line, 3);
    expect(diagnostics.last.severity, YosysDiagnosticSeverity.warning);
  });

  test('yosysErrorDiagnosticProvider returns an empty list on empty input', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(yosysErrorDiagnosticProvider('')), isEmpty);
  });

  test('parser override flows through to the family provider', () {
    final container = ProviderContainer(
      overrides: [
        yosysDiagnosticParserProvider.overrideWithValue(
          const YosysDiagnosticParser(),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(yosysDiagnosticParserProvider),
      isA<YosysDiagnosticParser>(),
    );
    expect(
      container
          .read(yosysErrorDiagnosticProvider('foo.v:1: ERROR: x'))
          .single
          .line,
      1,
    );
  });
}
