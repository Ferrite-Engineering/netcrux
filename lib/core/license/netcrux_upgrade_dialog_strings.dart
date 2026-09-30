// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Adapter that satisfies the cross-suite [CruxUpgradeDialogStrings]
/// interface from `package:crux_license` using NetCrux's ARB-generated
/// [L10N] strings.
///
/// The shared [CruxUpgradeDialog] accepts a [CruxUpgradeDialogStrings] so it
/// renders the same layout across every Crux product while pulling its text
/// from the product's active locale. NetCrux binds each member to its
/// existing `upgradeDialog*` / `commonOk` ARB keys, so the shared dialog
/// reads identically to the bespoke one it replaced.
class NetcruxUpgradeDialogStrings extends CruxUpgradeDialogStrings {
  /// Wraps the supplied [L10N] so the shared dialog renders in the active
  /// locale.
  const NetcruxUpgradeDialogStrings(this._l10n);

  final L10N _l10n;

  @override
  String get title => _l10n.upgradeDialogTitle;

  @override
  String body(String featureName, String tierName) =>
      _l10n.upgradeDialogMessage(featureName, tierName);

  @override
  String get tierNamePro => _l10n.upgradeDialogTierNamePro;

  @override
  String get tierNameEnterprise => _l10n.upgradeDialogTierNameEnterprise;

  @override
  String get dismissLabel => _l10n.commonOk;

  @override
  String get seePricingLabel => _l10n.upgradeDialogSeePricing;
}
