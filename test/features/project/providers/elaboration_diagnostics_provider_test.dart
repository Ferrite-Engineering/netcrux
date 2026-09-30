// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';

void main() {
  group('elaborationStderrProvider', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('defaults to empty', () {
      expect(container.read(elaborationStderrProvider), '');
    });

    test('set installs the value', () {
      container.read(elaborationStderrProvider.notifier).set('warning');
      expect(container.read(elaborationStderrProvider), 'warning');
    });

    test('clear resets to empty', () {
      container.read(elaborationStderrProvider.notifier)
        ..set('xyz')
        ..clear();
      expect(container.read(elaborationStderrProvider), '');
    });
  });

  group('elaborationDiagnosticsProvider', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('empty stderr → empty list', () {
      expect(
        container.read(elaborationDiagnosticsProvider),
        isEmpty,
      );
    });

    test('Yosys warning text parses into a YosysDiagnostic', () {
      container
          .read(elaborationStderrProvider.notifier)
          .set('Warning: top.v:42: signal foo unused');
      final entries = container.read(elaborationDiagnosticsProvider);
      expect(entries, isNotEmpty);
      expect(entries.first.severity, YosysDiagnosticSeverity.warning);
    });
  });

  group('elaborationDiagnosticFilterProvider', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('defaults to all severities', () {
      final filter = container.read(elaborationDiagnosticFilterProvider);
      expect(filter, hasLength(YosysDiagnosticSeverity.values.length));
    });

    test('toggle removes a severity', () {
      container
          .read(elaborationDiagnosticFilterProvider.notifier)
          .toggle(YosysDiagnosticSeverity.info);
      final filter = container.read(elaborationDiagnosticFilterProvider);
      expect(filter.contains(YosysDiagnosticSeverity.info), isFalse);
      expect(filter.contains(YosysDiagnosticSeverity.warning), isTrue);
    });

    test('toggle that would empty the filter resets it instead of '
        'producing an empty filter', () {
      final notifier =
          container.read(elaborationDiagnosticFilterProvider.notifier)
            ..toggle(YosysDiagnosticSeverity.info)
            ..toggle(YosysDiagnosticSeverity.warning)
            ..toggle(YosysDiagnosticSeverity.error);
      final filter = container.read(elaborationDiagnosticFilterProvider);
      // Removing the last entry triggers a reset to all severities.
      expect(filter, hasLength(YosysDiagnosticSeverity.values.length));
      notifier.reset(); // no-op when already at full set
      expect(
        container.read(elaborationDiagnosticFilterProvider),
        hasLength(YosysDiagnosticSeverity.values.length),
      );
    });
  });

  group('filteredElaborationDiagnosticsProvider', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('filters by severity', () {
      container
          .read(elaborationStderrProvider.notifier)
          .set(
            'Warning: top.v:1: w1\n'
            'ERROR: top.v:2: e1\n'
            'Info: top.v:3: i1\n',
          );
      // Drop warnings → only errors + info remain.
      container
          .read(elaborationDiagnosticFilterProvider.notifier)
          .toggle(YosysDiagnosticSeverity.warning);
      final shown = container.read(filteredElaborationDiagnosticsProvider);
      expect(
        shown.any((d) => d.severity == YosysDiagnosticSeverity.warning),
        isFalse,
      );
      expect(
        shown.any((d) => d.severity == YosysDiagnosticSeverity.error),
        isTrue,
      );
    });
  });
}
