// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_options.dart';
import 'package:netcrux/domain/models/cdc/cdc_severity.dart';

void main() {
  group('CdcAnalysisOptions', () {
    test('defaults match the documented defaults', () {
      const o = CdcAnalysisOptions.defaults;
      expect(o.scopeFilter, isNull);
      expect(o.userSynchronizerPatterns, isEmpty);
      expect(o.minSeverityToReport, CdcSeverity.info);
      expect(o.maxPathDepth, 10);
    });

    test('copyWith replaces only requested fields', () {
      const scope = ElementId(kind: ElementKind.scope, path: 'top.cpu');
      const o = CdcAnalysisOptions.defaults;
      final next = o.copyWith(
        scopeFilter: scope,
        userSynchronizerPatterns: <String>['my_sync'],
        minSeverityToReport: CdcSeverity.warning,
        maxPathDepth: 20,
      );
      expect(next.scopeFilter, scope);
      expect(next.userSynchronizerPatterns, <String>['my_sync']);
      expect(next.minSeverityToReport, CdcSeverity.warning);
      expect(next.maxPathDepth, 20);
    });

    test('clearScopeFilter wipes the scope', () {
      const scope = ElementId(kind: ElementKind.scope, path: 'top.cpu');
      final scoped = CdcAnalysisOptions.defaults.copyWith(scopeFilter: scope);
      expect(scoped.scopeFilter, scope);
      final cleared = scoped.copyWith(clearScopeFilter: true);
      expect(cleared.scopeFilter, isNull);
    });

    test('equality compares every field including ordered patterns list', () {
      const a = CdcAnalysisOptions(
        userSynchronizerPatterns: <String>['a', 'b'],
      );
      const b = CdcAnalysisOptions(
        userSynchronizerPatterns: <String>['a', 'b'],
      );
      const c = CdcAnalysisOptions(
        userSynchronizerPatterns: <String>['b', 'a'],
      );
      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });

    test('toString surfaces salient fields', () {
      final s = CdcAnalysisOptions.defaults.toString();
      expect(s, contains('CdcAnalysisOptions'));
      expect(s, contains('maxDepth: 10'));
    });
  });
}
