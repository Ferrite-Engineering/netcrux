// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';

/// Whether this build and licence can show a Pro panel: the Pro overlay is
/// installed, and the licence reaches Pro (or the beta admits every tier).
///
/// The same rule the Pro-action gate applies, read without the upgrade dialog:
/// a collaborative session asks it on the follower's behalf, where nobody
/// chose the panel and a dialog would be an interruption, not an answer.
final collabProPanelsAvailableProvider = Provider<bool>((ref) {
  if (!ref.watch(proOverlayInstalledProvider)) return false;
  if (ref.watch(betaPeriodProvider)) return true;
  return ref.watch(licenseTierProvider).featureEquivalent.index >=
      LicenseTier.pro.index;
}, name: 'collabProPanelsAvailableProvider');

/// The Pro panel the presenter has in front that this follower cannot open,
/// or `null` when there is none.
///
/// View sync degrades, it never unlocks: a guest without Pro whose presenter
/// opens the CDC panel is told the presenter is showing something that
/// requires NetCrux Pro, and is not given the panel. A guest with Pro gets the
/// same panel over their own analysis state.
final collabDegradedPanelProvider = Provider<AnalysisPanelKind?>((ref) {
  final session = ref.watch(schematicCollabSessionProvider).value;
  if (session == null || session.isAwaitingAdmission) return null;
  if (session.isLocalPresenter) return null;
  final kind = analysisPanelKindNamed(session.presenterView?.analysisPanel);
  if (kind == null || !kind.requiresPro) return null;
  return ref.watch(collabProPanelsAvailableProvider) ? null : kind;
}, name: 'collabDegradedPanelProvider');
