// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:netcrux/core/license/netcrux_license_badge_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Thin context-aware wrapper around the cross-suite [FeatureTierBadge] widget
/// that supplies a [NetCruxLicenseBadgeStrings] adapter built from the
/// nearest [L10N], so feature call sites do not need to construct the
/// adapter themselves.
///
/// Pass [LicenseTier.openCore] (or [LicenseTier.edu]) and the widget
/// collapses to `SizedBox.shrink()`, making it safe to wrap any feature
/// label unconditionally.
class NetCruxFeatureTierBadge extends StatelessWidget {
  /// Creates a tier badge labelling a feature that requires [requiredTier].
  const NetCruxFeatureTierBadge({required this.requiredTier, super.key});

  /// Minimum tier required to activate the feature this badge labels.
  final LicenseTier requiredTier;

  @override
  Widget build(BuildContext context) {
    return FeatureTierBadge(
      requiredTier: requiredTier,
      strings: NetCruxLicenseBadgeStrings(L10N.of(context)),
    );
  }
}
