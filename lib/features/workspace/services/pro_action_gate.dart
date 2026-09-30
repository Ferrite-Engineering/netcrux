// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_upgrade_dialog.dart';

/// Returns true when [action] may run in this build under the active
/// licence — and when it may not, tells the user why. Reads the action's
/// declared [NetcruxActionRequiredTier.requiredTier], so a single guard
/// serves every Pro-tier action.
///
/// Consults the OVERRIDABLE [betaPeriodProvider] rather than
/// [FeatureGate.isAvailable] — which reads the compile-time
/// `kBetaPeriod` constant a Riverpod override cannot move. During the
/// public beta ([betaPeriodProvider] `true`) the gate short-circuits to
/// allow regardless of tier (badges stay visible; activation is never
/// blocked). Post-beta ([betaPeriodProvider] `false`) an insufficient
/// tier denies the dispatch and shows the [NetcruxUpgradeDialog] — the
/// action stays discoverable and enabled in the menu / command palette,
/// and activation explains which tier unlocks it, until a license whose
/// [LicenseTier.featureEquivalent] satisfies the action's required tier
/// is installed (so EDU satisfies a Pro gate). Reading the provider is
/// what makes the post-beta denial branch testable ahead of the beta
/// flip.
///
/// An admitted Pro-tier action in a build with no Pro overlay
/// ([proOverlayInstalledProvider] `false`) has nothing behind it, so it is
/// refused with a "requires NetCrux Pro" snackbar rather than dispatched to
/// the open-core no-op — during the beta that is the only feedback an
/// open-core user gets.
///
/// Calling this for an open-core action is harmless — its `requiredTier`
/// is [LicenseTier.openCore], which every tier satisfies — so the
/// dispatcher wraps only the Pro-tier cases (the "clear / dismiss" actions
/// stay unconditional by design). Surfaces outside the dispatcher that run
/// a Pro action directly — the inspector's Go to source — call it too. The
/// docked cross-probe panel's per-peer send does not: it is not an action,
/// and its send is implemented in open core, so it dispatches with or without
/// an overlay. It asks `crossProbeOriginateGateProvider`, which applies the
/// same tier gate without the "requires NetCrux Pro" refusal.
bool allowProAction(
  BuildContext context,
  WidgetRef ref,
  NetcruxAction action,
) {
  final beta = ref.read(betaPeriodProvider);
  final tier = ref.read(licenseTierProvider);
  final allowed =
      beta || tier.featureEquivalent.index >= action.requiredTier.index;
  if (!allowed) {
    // `tier.gate_hit` — the commercial telemetry group. The gate
    // DENIAL is the seam, not the gate: `FeatureGate.satisfiesTier` /
    // `isAvailable` are pure predicates called from `build()`, and recording
    // there would fire on every rebuild and produce volume instead of signal.
    //
    // This branch is unreachable for the whole beta — `betaPeriodProvider` is
    // true, so `allowed` is true whatever the tier. That is not dead code to
    // be tidied away: it matches telemetry's own dark launch (nothing is
    // collected during the beta), and the
    // post-beta branch is exercised by overriding the provider, which is why
    // the gate reads it instead of the compile-time `kBetaPeriod`.
    //
    // `feature` is the closed-vocabulary id, NEVER the localized
    // `featureLabel` passed to the same dialog — see [NetcruxGatedFeature].
    // `required` is `requiredTier.name`, which is `pro` or `enterprise`
    // here: an open-core action satisfies every tier and so never reaches
    // this branch. No `tier` property either; the tier the user HOLDS is
    // `license_tier` in the envelope.
    //
    // Recorded from `onOpened`, so only a denial that opens a dialog counts.
    // A held chord re-dispatches the denial on every key repeat, and the
    // dialog's guard suppresses all but the first; counted before the
    // guard, each repeat would read as another user asking to upgrade.
    final feature = action.gatedFeature;
    final telemetry = ref.read(telemetryServiceProvider);
    unawaited(
      NetcruxUpgradeDialog.show(
        context,
        featureLabel: action.label(L10N.of(context)),
        requiredTier: action.requiredTier,
        onOpened: feature == null
            ? null
            : () => telemetry.record(
                TelemetryEvent(
                  'tier.gate_hit',
                  properties: <String, Object?>{
                    'feature': telemetryEnumToken(feature),
                    'required': action.requiredTier.name,
                  },
                ),
              ),
      ),
    );
    return false;
  }
  if (action.requiredTier != LicenseTier.openCore &&
      !ref.read(proOverlayInstalledProvider)) {
    final l10n = L10N.of(context);
    showCruxInfoSnack(context, l10n.actionRequiresPro(action.label(l10n)));
    return false;
  }
  return true;
}
