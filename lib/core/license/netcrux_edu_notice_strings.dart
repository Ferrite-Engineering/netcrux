// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// The product name the educational export mark carries. A brand, so it is
/// not localized.
const String kNetcruxEduMarkProductName = 'NetCrux';

/// NetCrux's localized [CruxEduNoticeStrings]: the educational licence's
/// status-bar label and tooltip. The mark stamped on visual exports is the
/// English one in every locale (see [netcruxEduExportMark]).
///
/// Lives in open core beside the status bar and the exporters that use it.
/// Open core never runs on an educational licence, so here the strings are
/// never shown; the Pro overlay supplies the licence status that makes them
/// appear.
class NetCruxEduNoticeStrings extends CruxEduNoticeStrings {
  /// Wraps the localizations for the nearest context.
  const NetCruxEduNoticeStrings(this._l10n);

  final L10N _l10n;

  @override
  String get statusLabel => _l10n.eduNoticeStatusLabel;

  @override
  String statusTooltip({String? email, String? validUntil}) {
    final holder = email == null
        ? _l10n.eduNoticeTooltip
        : _l10n.eduNoticeTooltipFor(email);
    return validUntil == null
        ? holder
        : '$holder ${_l10n.eduNoticeValidUntil(validUntil)}';
  }

  /// English in every locale, like [netcruxEduExportMark]: the mark is
  /// written into a file that travels, not shown in this user's interface.
  @override
  String exportMark(String productName) =>
      const CruxEduNoticeStringsEn().exportMark(productName);
}

/// The mark to stamp on a NetCrux visual export (PNG, SVG, review-minutes
/// Markdown) made under [status], or `null` for every tier but Educational.
///
/// Always English, whatever the interface language: an exported file is read
/// by whoever it is sent to, and the suite's exports and reports state the
/// licence in one language.
///
/// Never applied to data a tool reads back: the netlist JSON slice, session
/// and project files, colour themes and shortcut maps stay byte-identical
/// under every licence.
String? netcruxEduExportMark(CruxLicenseStatus status) =>
    cruxEduExportMark(status, kNetcruxEduMarkProductName);
