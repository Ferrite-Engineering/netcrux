// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/license/netcrux_gated_feature.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_upgrade_dialog.dart';

/// Decides whether this seat may **originate** a cross-probe, and explains
/// itself when it may not.
///
/// Returns `true` when the send may proceed. When it returns `false` it has
/// already told the user why, so the caller simply returns. A user pressed a
/// button; the one answer that is never acceptable is nothing.
typedef CrossProbeOriginateGate = bool Function(BuildContext context);

/// The tier that originating a cross-probe requires once the beta ends.
///
/// One constant for the two places that state it: the gate below, which
/// enforces it, and the cross-probe panel's send-button badge, which labels it
/// before the click. Two literals could drift apart; one cannot.
const LicenseTier kCrossProbeOriginateRequiredTier = LicenseTier.pro;

/// The gate the cross-probe panel's per-peer send button consults.
///
/// ### Why the panel needs a gate of its own
///
/// Cross-probe *origination* — pointing another product at the selected
/// element — is a Pro capability. The Pro overlay gates its own route to it,
/// the schematic context menu's "Send to …" entries. But the docked
/// cross-probe panel ships in open core, is mounted from the open-core dock,
/// and carries a send button per discovered peer that reaches the very same
/// capability. Without this seam that button was a second, unguarded route:
/// the paywall existed on one door and not the other.
///
/// The same rule applies to any priced capability whose code lives in open
/// core: the gate lives beside the code, in open core, reading the suite's
/// own tier providers — not in the overlay, where it would only guard the
/// overlay's door.
///
/// ### What it does
///
/// The answer the workspace action dispatcher gives every Pro-tier action,
/// because this is one more of them: admitted while the public beta is in
/// effect (`betaPeriodProvider`), and afterwards for a tier that satisfies
/// Pro (EDU and Enterprise pass). A post-beta denial records `tier.gate_hit`
/// under [NetcruxGatedFeature.crossProbe] — the id the overlay's menu entries
/// share, because the two doors open onto one capability — and raises the
/// open-core [NetcruxUpgradeDialog], which names the tier.
///
/// Unlike the dispatcher, there is no "no Pro overlay behind it" refusal:
/// the panel's send is implemented here, in open core, and dispatches
/// whether or not an overlay is installed. The tier is the only question.
///
/// NetCrux keeps its upgrade dialog in open core, so nothing here needs the
/// overlay to rebind it; the seam still exists so a test can prove the panel
/// asks it, and so a product whose dialog lives in its overlay can follow the
/// same shape by overriding it.
final Provider<CrossProbeOriginateGate> crossProbeOriginateGateProvider =
    Provider<CrossProbeOriginateGate>(
      (ref) => (context) {
        final unlocked =
            ref.read(betaPeriodProvider) ||
            FeatureGate.satisfiesTier(
              kCrossProbeOriginateRequiredTier,
              ref.read(licenseTierProvider),
            );
        if (unlocked) return true;
        if (!context.mounted) return false;
        // Unreachable for the whole beta, on purpose: it goes live with the
        // flag that ends it, like every other gate-hit site. Recorded from
        // `onOpened`, so a denial while an upgrade dialog is already up
        // counts nothing, as at the other sites.
        final telemetry = ref.read(telemetryServiceProvider);
        unawaited(
          NetcruxUpgradeDialog.show(
            context,
            featureLabel: L10N.of(context).crossProbeSendTooltip,
            requiredTier: kCrossProbeOriginateRequiredTier,
            onOpened: () => telemetry.record(
              TelemetryEvent(
                'tier.gate_hit',
                properties: <String, Object?>{
                  'feature': telemetryEnumToken(NetcruxGatedFeature.crossProbe),
                  'required': kCrossProbeOriginateRequiredTier.name,
                },
              ),
            ),
          ),
        );
        return false;
      },
      name: 'crossProbeOriginateGateProvider',
    );
