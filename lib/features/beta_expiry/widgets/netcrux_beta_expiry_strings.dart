// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// NetCrux-localized [CruxBetaExpiryStrings] adapter.
///
/// `crux_license` ships [CruxBetaExpiryStringsEn] as a bare-English default so
/// the banner can be dropped into a test without wiring localization; products
/// subclass the interface and route each member through their own [L10N]. The
/// three keys already existed in all five of NetCrux's ARB files — the banner
/// was hand-copied here before it was lifted into `crux_license`, so this is a
/// re-binding, not a translation job.
class NetcruxBetaExpiryStrings extends CruxBetaExpiryStrings {
  /// Wraps the supplied [L10N] so each member resolves in the active locale.
  const NetcruxBetaExpiryStrings(this._l10n);

  final L10N _l10n;

  @override
  String bannerMessage(int days) => _l10n.betaExpiryBannerMessage(days);

  @override
  String get bannerAction => _l10n.betaExpiryBannerAction;

  @override
  String get dismissLabel => _l10n.betaExpiryDismissLabel;
}

/// NetCrux-localized [CruxBetaExpiredStrings] adapter for the blocking
/// expired modal, `CruxBetaExpiredOverlay`.
///
/// The four keys were the strings of NetCrux's own copy of that modal before
/// it was lifted into `crux_license`, so this too is a re-binding, not a
/// translation job.
class NetcruxBetaExpiredStrings extends CruxBetaExpiredStrings {
  /// Wraps the supplied [L10N] so each member resolves in the active locale.
  const NetcruxBetaExpiredStrings(this._l10n);

  final L10N _l10n;

  @override
  String get title => _l10n.betaExpiryExpiredTitle;

  @override
  String get body => _l10n.betaExpiryExpiredBody;

  @override
  String get downloadLabel => _l10n.betaExpiryExpiredAction;

  @override
  String get quitLabel => _l10n.betaExpiryExpiredQuit;
}
