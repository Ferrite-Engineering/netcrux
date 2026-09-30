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
