// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Adapter that satisfies the cross-suite [CruxUpdateStrings] interface from
/// `package:crux_updates` using NetCrux's ARB-generated [L10N] strings.
///
/// `crux_shared` packages carry no ARB files, so every product supplies an
/// adapter of this shape — the same pattern as `NetCruxLicenseBadgeStrings`
/// and `NetcruxAboutStrings`.
///
/// The product name lives in NetCrux's own ARB entry
/// (`"NetCrux {version} is available."`), which is why [bannerMessage] takes
/// only the version: interpolation order stays inside the ARB file.
class NetcruxUpdateStrings extends CruxUpdateStrings {
  /// Wraps the supplied [L10N] so the package's banner and manual-check
  /// action render in the active locale.
  const NetcruxUpdateStrings(this._l10n);

  final L10N _l10n;

  @override
  String bannerMessage(String version) => _l10n.updateBannerMessage(version);

  @override
  String get viewChangesAction => _l10n.updateViewChangesAction;

  @override
  String get updateNowAction => _l10n.updateNowAction;

  @override
  String get dismissLabel => _l10n.updateDismissLabel;

  @override
  String get checkInProgress => _l10n.updateCheckInProgress;

  @override
  String checkUpToDate(String version) => _l10n.updateCheckUpToDate(version);

  @override
  String get checkFailed => _l10n.updateCheckFailed;
}
