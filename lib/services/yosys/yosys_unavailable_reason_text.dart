// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Maps a `YosysAvailability.unavailableReason` code to a localized,
/// actionable explanation.
///
/// The reason is carried as a `String?` rather than an enum, so a build
/// of `crux_yosys` newer than this one can report a code NetCrux does
/// not model. An unrecognized code returns `null` and the caller falls
/// back to its generic message — the probe result stays usable rather
/// than rendering a raw wire code at the user.
///
/// The four codes differ in what the user must do about them: a missing
/// binary is an install problem, a stalled probe is usually a network
/// mount, an exec failure is a broken binary or a sandbox denial, and an
/// unparsed banner is a build NetCrux does not recognize. Collapsing
/// them into one message sends the user to the wrong fix.
String? yosysUnavailableReasonText(L10N l10n, String? reason) {
  switch (reason) {
    case YosysUnavailableReason.notOnPath:
      return l10n.yosysReasonNotOnPath;
    case YosysUnavailableReason.execFailed:
      return l10n.yosysReasonExecFailed;
    case YosysUnavailableReason.bannerUnparsed:
      return l10n.yosysReasonBannerUnparsed;
    case YosysUnavailableReason.probeTimedOut:
      return l10n.yosysReasonProbeTimedOut;
    case _:
      return null;
  }
}
