// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Adapter that satisfies the cross-suite [LicenseBadgeStrings] interface
/// from `package:crux_license` using NetCrux's ARB-generated [L10N] strings.
///
/// The package's [FeatureTierBadge] and [EditionBadge] widgets accept a
/// [LicenseBadgeStrings] in their constructors so they can render in the
/// product's active locale without baking in English text. Each Crux
/// product ships an adapter of this shape; see WaveCrux's
/// `WaveCruxLicenseBadgeStrings` for the canonical reference.
class NetCruxLicenseBadgeStrings extends LicenseBadgeStrings {
  /// Wraps the supplied [L10N] so the package badge widgets can render
  /// in the active locale.
  const NetCruxLicenseBadgeStrings(this._l10n);

  final L10N _l10n;

  @override
  String get tierBadgePro => _l10n.tierBadgePro;

  @override
  String get tierBadgeProSemantic => _l10n.tierBadgeProSemantic;

  @override
  String get tierBadgeEnterprise => _l10n.tierBadgeEnterprise;

  @override
  String get tierBadgeEnterpriseSemantic => _l10n.tierBadgeEnterpriseSemantic;

  @override
  String get tierBadgeEdu => _l10n.tierBadgeEdu;

  @override
  String get tierBadgeEduSemantic => _l10n.tierBadgeEduSemantic;

  @override
  String get editionBadgeEduSemantic => _l10n.editionBadgeEduSemantic;

  @override
  String get editionBadgeProSemantic => _l10n.editionBadgeProSemantic;

  @override
  String get editionBadgeEnterpriseSemantic =>
      _l10n.editionBadgeEnterpriseSemantic;
}
