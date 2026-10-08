// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';

void main() {
  test('bookmarks and annotations are open core; every analysis is Pro', () {
    expect(
      [
        for (final k in AnalysisPanelKind.values)
          if (!k.requiresPro) k,
      ],
      [AnalysisPanelKind.bookmarks, AnalysisPanelKind.annotations],
    );
  });

  test("a panel's tier agrees with the action that shows it", () {
    // One fact seen twice; if a panel's action changes tier, this says so.
    const shownBy = {
      AnalysisPanelKind.cdc: NetcruxAction.showCdcAnalysisPane,
      AnalysisPanelKind.resetDomain: NetcruxAction.showResetDomainAnalysisPane,
      AnalysisPanelKind.fsm: NetcruxAction.showFsmBubbleDiagram,
      AnalysisPanelKind.activity: NetcruxAction.showActivityHeatmap,
      AnalysisPanelKind.diff: NetcruxAction.showDiffPane,
      AnalysisPanelKind.source: NetcruxAction.showSourcePane,
      AnalysisPanelKind.bookmarks: NetcruxAction.showBookmarksPanel,
      AnalysisPanelKind.annotations: NetcruxAction.showAnnotationsPanel,
    };
    shownBy.forEach((kind, action) {
      expect(
        kind.requiresPro,
        action.requiredTier != LicenseTier.openCore,
        reason: '$kind / $action',
      );
    });
  });

  test('a name a later build might send resolves to nothing', () {
    expect(analysisPanelKindNamed('cdc'), AnalysisPanelKind.cdc);
    expect(analysisPanelKindNamed('timingReport'), isNull);
    expect(analysisPanelKindNamed(null), isNull);
  });
}
