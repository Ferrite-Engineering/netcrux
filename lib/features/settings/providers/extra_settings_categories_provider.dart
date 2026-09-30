// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core extension point: additional Settings categories contributed by
/// an overlay, appended after the built-in open-core categories.
///
/// Open-core returns an empty list. The seam exists in every Crux app, so a
/// Pro overlay category lands the same way in NetCrux as in the other three —
/// via the suite-shared [CruxSettingsExtraCategory] (stable id, required
/// icon, context-taking label/body builders).
final extraSettingsCategoriesProvider =
    Provider<List<CruxSettingsExtraCategory>>((_) => const []);
