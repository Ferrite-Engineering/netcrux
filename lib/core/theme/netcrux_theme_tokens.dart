// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';

/// Registers NetCrux's themable-token catalogs with the shared
/// [ThemeRegistry]. Called once from [bootstrap]; idempotent so a
/// second bootstrap (test hot-restart, doubled init) is a no-op.
///
/// NetCrux currently only registers the suite-shared `chrome` catalog
/// — the app's product panes (CDC analysis, FSM, diff, source preview)
/// don't yet have a curated theme-token catalog. When they do, register
/// the additional category here alongside the chrome call.
void registerNetcruxThemeTokens() {
  registerCruxThemeChromeTokens();
}
