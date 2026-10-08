// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';
import 'package:netcrux/features/collaboration/collab_view_degradation_provider.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';

SchematicCollabSessionState _following(String? panel, {String me = 'grace'}) =>
    SchematicCollabSessionState(
      sessionId: 'ABC123',
      myParticipantId: me,
      hostId: 'ada',
      mode: SchematicCollabMode.lan,
      presenterView: SchematicCollabPresenterView(
        scopePath: '',
        analysisPanel: panel,
      ),
    );

AnalysisPanelKind? _degraded(
  SchematicCollabSessionState state, {
  bool overlay = true,
  bool beta = false,
  LicenseTier tier = LicenseTier.openCore,
}) {
  final container = ProviderContainer(
    overrides: [
      schematicCollabSessionProvider.overrideWithValue(AsyncData(state)),
      proOverlayInstalledProvider.overrideWithValue(overlay),
      betaPeriodProvider.overrideWithValue(beta),
      licenseTierProvider.overrideWithValue(tier),
    ],
  );
  addTearDown(container.dispose);
  return container.read(collabDegradedPanelProvider);
}

void main() {
  test('an unlicensed guest is told about a Pro panel, not given it', () {
    expect(_degraded(_following('cdc')), AnalysisPanelKind.cdc);
  });

  test('a guest with Pro (or EDU, or during the beta) gets the panel', () {
    expect(_degraded(_following('cdc'), tier: LicenseTier.pro), isNull);
    expect(_degraded(_following('cdc'), tier: LicenseTier.edu), isNull);
    expect(_degraded(_following('cdc'), beta: true), isNull);
  });

  test('a build without the Pro overlay is degraded whatever the tier', () {
    expect(
      _degraded(_following('fsm'), overlay: false, tier: LicenseTier.pro),
      AnalysisPanelKind.fsm,
    );
  });

  test('open-core panels never degrade', () {
    expect(_degraded(_following('annotations')), isNull);
    expect(_degraded(_following('bookmarks')), isNull);
  });

  test('nothing for the presenter, no panel, or a panel this build lacks', () {
    expect(_degraded(_following('cdc', me: 'ada')), isNull);
    expect(_degraded(_following(null)), isNull);
    expect(_degraded(_following('timingReport')), isNull);
  });
}
