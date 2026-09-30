// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';

void main() {
  test('defaults describe the empty workspace', () {
    const ctx = NetcruxActionContext();
    expect(ctx.hasOpenTab, isFalse);
    expect(ctx.hasNetlist, isFalse);
    expect(ctx.hasSelection, isFalse);
    expect(ctx.hasTraceOverlay, isFalse);
    expect(ctx.hasXTraceResult, isFalse);
    expect(ctx.comparisonActive, isFalse);
    expect(ctx.waveformLoaded, isFalse);
    expect(ctx.cdcAnalysisPresent, isFalse);
    expect(ctx.resetAnalysisPresent, isFalse);
    expect(ctx.fsmFocused, isFalse);
    expect(ctx.activityColoringActive, isFalse);
    expect(ctx.paneCount, 1);
    expect(ctx.isBrowser, isFalse);
  });

  test('equality + hashCode cover every field', () {
    const base = NetcruxActionContext();
    expect(base, const NetcruxActionContext());
    expect(base.hashCode, const NetcruxActionContext().hashCode);

    const variants = <NetcruxActionContext>[
      NetcruxActionContext(hasOpenTab: true),
      NetcruxActionContext(hasNetlist: true),
      NetcruxActionContext(hasSelection: true),
      NetcruxActionContext(hasTraceOverlay: true),
      NetcruxActionContext(hasXTraceResult: true),
      NetcruxActionContext(comparisonActive: true),
      NetcruxActionContext(waveformLoaded: true),
      NetcruxActionContext(cdcAnalysisPresent: true),
      NetcruxActionContext(resetAnalysisPresent: true),
      NetcruxActionContext(fsmFocused: true),
      NetcruxActionContext(activityColoringActive: true),
      NetcruxActionContext(paneCount: 2),
      NetcruxActionContext(tabCountInActivePane: 2),
      NetcruxActionContext(isBrowser: true),
    ];
    for (final variant in variants) {
      expect(variant, isNot(base), reason: '$variant must differ from base');
    }
  });
}
