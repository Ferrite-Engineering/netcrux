// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain_analysis_options.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';

void main() {
  group('ResetDomainAnalysisOptions', () {
    test('defaults instance has expected defaults', () {
      const o = ResetDomainAnalysisOptions.defaults;
      expect(o.scopeFilter, isNull);
      expect(o.userSynchronizerPatterns, isEmpty);
      expect(o.minSeverityToReport, ResetSeverity.info);
      expect(o.maxPathDepth, 10);
    });

    test('copyWith replaces only requested fields', () {
      const o = ResetDomainAnalysisOptions.defaults;
      final next = o.copyWith(
        maxPathDepth: 25,
        minSeverityToReport: ResetSeverity.warning,
      );
      expect(next.maxPathDepth, 25);
      expect(next.minSeverityToReport, ResetSeverity.warning);
    });

    test('clearScopeFilter zeroes the scope', () {
      const scoped = ResetDomainAnalysisOptions(
        scopeFilter: ElementId(kind: ElementKind.scope, path: 'top.cpu'),
      );
      final next = scoped.copyWith(clearScopeFilter: true);
      expect(next.scopeFilter, isNull);
    });

    test('equality + hashCode match field-by-field', () {
      const a = ResetDomainAnalysisOptions.defaults;
      const b = ResetDomainAnalysisOptions.defaults;
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      final c = a.copyWith(maxPathDepth: 42);
      expect(c == a, isFalse);
    });

    test('userSynchronizerPatterns deep equality', () {
      const a = ResetDomainAnalysisOptions(
        userSynchronizerPatterns: <String>['my_sync', 'rst_synchronizer'],
      );
      const b = ResetDomainAnalysisOptions(
        userSynchronizerPatterns: <String>['my_sync', 'rst_synchronizer'],
      );
      expect(a == b, isTrue);
      const c = ResetDomainAnalysisOptions(
        userSynchronizerPatterns: <String>['my_sync', 'other'],
      );
      expect(a == c, isFalse);
    });

    test('toString surfaces the salient fields', () {
      const o = ResetDomainAnalysisOptions.defaults;
      final s = o.toString();
      expect(s, contains('ResetDomainAnalysisOptions'));
      expect(s, contains('maxDepth: 10'));
    });
  });
}
