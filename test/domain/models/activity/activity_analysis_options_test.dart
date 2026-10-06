// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/activity_analysis_options.dart';
import 'package:netcrux/domain/models/activity/activity_normalization.dart';
import 'package:netcrux/domain/models/activity/waveform_time_range.dart';

void main() {
  const scope = ElementId(kind: ElementKind.scope, path: 'top.cpu');
  const otherScope = ElementId(kind: ElementKind.scope, path: 'top.mem');
  const window = WaveformTimeRange(startNs: 10, endNs: 90, label: 'mid');

  group('defaults', () {
    test('documented default values', () {
      const o = ActivityAnalysisOptions.defaults;
      expect(o.scopeFilter, isNull);
      expect(o.timeRange, WaveformTimeRange.fullSimulationSentinel);
      expect(o.normalization, ActivityNormalization.rank);
      expect(o.topN, 50);
      expect(o.excludedNetPaths, isEmpty);
    });
  });

  group('copyWith', () {
    test('no arguments preserves every field', () {
      const original = ActivityAnalysisOptions(
        scopeFilter: scope,
        timeRange: window,
        normalization: ActivityNormalization.logScale,
        topN: 7,
        excludedNetPaths: <String>['top.clk'],
      );
      expect(original.copyWith(), original);
    });

    test('replaces each field independently', () {
      const base = ActivityAnalysisOptions.defaults;
      expect(base.copyWith(scopeFilter: scope).scopeFilter, scope);
      expect(base.copyWith(timeRange: window).timeRange, window);
      expect(
        base
            .copyWith(normalization: ActivityNormalization.globalMax)
            .normalization,
        ActivityNormalization.globalMax,
      );
      expect(base.copyWith(topN: 3).topN, 3);
      expect(
        base.copyWith(excludedNetPaths: const <String>['a']).excludedNetPaths,
        const <String>['a'],
      );
    });

    test('clearScopeFilter resets the scope even when one is set', () {
      const scoped = ActivityAnalysisOptions(scopeFilter: scope);
      expect(scoped.copyWith(clearScopeFilter: true).scopeFilter, isNull);
    });

    test('clearScopeFilter wins over a simultaneously-passed scope', () {
      const scoped = ActivityAnalysisOptions(scopeFilter: scope);
      final cleared = scoped.copyWith(
        scopeFilter: otherScope,
        clearScopeFilter: true,
      );
      expect(cleared.scopeFilter, isNull);
    });
  });

  group('value semantics', () {
    test('identical field sets compare equal and share a hash', () {
      const a = ActivityAnalysisOptions(
        scopeFilter: scope,
        timeRange: window,
        normalization: ActivityNormalization.logScale,
        topN: 7,
        excludedNetPaths: <String>['top.clk', 'top.rst'],
      );
      const b = ActivityAnalysisOptions(
        scopeFilter: scope,
        timeRange: window,
        normalization: ActivityNormalization.logScale,
        topN: 7,
        excludedNetPaths: <String>['top.clk', 'top.rst'],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, a);
    });

    test('every field participates in equality', () {
      const base = ActivityAnalysisOptions.defaults;
      expect(base, isNot(base.copyWith(scopeFilter: scope)));
      expect(base, isNot(base.copyWith(timeRange: window)));
      expect(
        base,
        isNot(base.copyWith(normalization: ActivityNormalization.logScale)),
      );
      expect(base, isNot(base.copyWith(topN: 1)));
      expect(
        base,
        isNot(base.copyWith(excludedNetPaths: const <String>['a'])),
      );
    });

    test('exclusion lists compare element-wise, order-sensitively', () {
      const ab = ActivityAnalysisOptions(
        excludedNetPaths: <String>['a', 'b'],
      );
      const ba = ActivityAnalysisOptions(
        excludedNetPaths: <String>['b', 'a'],
      );
      const aOnly = ActivityAnalysisOptions(excludedNetPaths: <String>['a']);
      expect(ab, isNot(ba));
      expect(ab, isNot(aOnly));
    });

    test('a non-options object is never equal', () {
      expect(ActivityAnalysisOptions.defaults, isNot(Object()));
    });
  });

  group('toString', () {
    test('renders "all" when unscoped', () {
      expect(ActivityAnalysisOptions.defaults.toString(), contains('all'));
    });

    test('renders the scope path, normalization name and exclusion count', () {
      const o = ActivityAnalysisOptions(
        scopeFilter: scope,
        normalization: ActivityNormalization.logScale,
        excludedNetPaths: <String>['a', 'b'],
      );
      final text = o.toString();
      expect(text, contains('top.cpu'));
      expect(text, contains('logScale'));
      expect(text, contains('excluded: 2'));
    });
  });
}
