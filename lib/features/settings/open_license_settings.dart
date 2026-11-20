// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:netcrux/features/settings/screens/settings_screen.dart';

/// Opens Settings at the License category, from the root navigator above
/// [context].
///
/// The one way into Settings > License: the licence-expiry strip, which sits
/// above the navigator and passes the root navigator's own context, and the
/// educational-licence chip in a tab's status bar, which sits below it. Both
/// land on the root navigator, so the surface is window-modal wherever the
/// request came from.
void openLicenseSettings(BuildContext context) {
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  unawaited(
    SettingsScreen.openAdaptive(
      navigator?.context ?? context,
      initialCategoryId: kCruxLicenseCategoryId,
    ),
  );
}
