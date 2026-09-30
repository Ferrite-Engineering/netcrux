// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:netcrux/core/license/netcrux_license_badge_strings.dart';
import 'package:netcrux/core/license/netcrux_upgrade_dialog_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// NetCrux binding of the cross-suite [CruxUpgradeDialog], shown when a
/// Pro/Enterprise action is activated post-beta under a license tier that
/// does not include it.
///
/// This is the suite's gate-denial convention: tier-gated items stay
/// enabled and tier-badged on every discovery surface, and an
/// insufficient-tier *activation* surfaces this dialog instead of a
/// silent no-op — the user learns why nothing happened and which tier
/// unlocks the feature. During the beta the gate short-circuits to
/// allow, so this dialog is unreachable until the beta flip.
///
/// The dialog body, badge, and layout come from the shared
/// [CruxUpgradeDialog]; this widget only supplies the NetCrux locale
/// adapters ([NetcruxUpgradeDialogStrings] and [NetCruxLicenseBadgeStrings])
/// built from the nearest [L10N], mirroring how [NetCruxFeatureTierBadge] wraps the
/// shared [FeatureTierBadge]. License-key entry / purchase flows live in the Pro
/// overlay and are not referenced here.
class NetcruxUpgradeDialog extends StatelessWidget {
  /// Creates the dialog. [featureLabel] is the localized label of the
  /// activated action; [requiredTier] is the tier that unlocks it.
  const NetcruxUpgradeDialog({
    required this.featureLabel,
    required this.requiredTier,
    super.key,
  });

  /// Localized label of the action the user activated.
  final String featureLabel;

  /// Minimum tier that unlocks the action ([LicenseTier.pro] or
  /// [LicenseTier.enterprise]).
  final LicenseTier requiredTier;

  /// Shows the dialog over [context], through the shared
  /// [CruxUpgradeDialog.show], and resolves when it is dismissed.
  ///
  /// Re-entrancy guarded by that opener, under
  /// [CruxUpgradeDialog.modalGuardKey]: holding a gated action's shortcut
  /// (key auto-repeat re-dispatches the denial) stacks no second dialog, and
  /// the suppressed call resolves immediately.
  ///
  /// [onOpened] runs only when this call opens a dialog, never for one the
  /// guard suppresses. Gate-denial sites record `tier.gate_hit` there, so the
  /// upgrade funnel counts the dialogs a user saw rather than the repeats of
  /// a held key.
  static Future<void> show(
    BuildContext context, {
    required String featureLabel,
    required LicenseTier requiredTier,
    VoidCallback? onOpened,
  }) {
    // The question the shared opener asks before it opens, under the one key
    // every upgrade dialog shares, so a suppressed call is known here.
    if (ModalGuard.isOpen(CruxUpgradeDialog.modalGuardKey)) {
      return Future<void>.value();
    }
    onOpened?.call();
    final l10n = L10N.of(context);
    return CruxUpgradeDialog.show(
      context,
      featureName: featureLabel,
      requiredTier: requiredTier,
      strings: NetCruxLicenseBadgeStrings(l10n),
      l10n: NetcruxUpgradeDialogStrings(l10n),
      // The dialog offers a way to act on what it just said.
      // Resolves to null in an open-core build, which has nothing to sell,
      // so the button is absent rather than dead.
      onSeePricing: cruxSeePricingActionFor(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return CruxUpgradeDialog(
      featureName: featureLabel,
      requiredTier: requiredTier,
      strings: NetCruxLicenseBadgeStrings(l10n),
      l10n: NetcruxUpgradeDialogStrings(l10n),
      onSeePricing: cruxSeePricingActionFor(context),
    );
  }
}
