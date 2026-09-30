// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:netcrux/core/license/netcrux_license_badge_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// NetCrux-flavored wrapper around the cross-suite
/// `package:crux_license/crux_license.dart` [EditionBadge].
///
/// Reads [L10N] from the current [BuildContext] and supplies a
/// [NetCruxLicenseBadgeStrings] adapter so the package widget renders the
/// localized chip without each call site constructing the adapter itself.
///
/// States the edition in force — EDU, PRO or ENT — and renders nothing at
/// open core. It takes no tier: the package widget reads
/// `licenseTierProvider` itself, because a statement about what the user owns
/// has exactly one correct source. Rendering nothing at open core is what makes
/// it safe to mount unconditionally in the status bar's trailing slot.
class NetCruxEditionBadge extends StatelessWidget {
  /// Creates an edition badge for the licence currently in force.
  const NetCruxEditionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return EditionBadge(
      strings: NetCruxLicenseBadgeStrings(L10N.of(context)),
    );
  }
}
