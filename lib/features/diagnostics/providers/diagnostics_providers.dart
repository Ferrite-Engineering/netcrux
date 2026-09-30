// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';

/// Whether NetCrux's diagnostics surfaces are available.
///
/// Gates all three surfaces — the Tab Diagnostics drawer, the App
/// Diagnostics dialog, and the Pane Render Stats popover — so a user who
/// turns diagnostics off gets a consistent app rather than two of the three
/// disappearing.
///
/// **Unconditionally true in debug and profile builds.** Those are the
/// builds where someone is looking at frame times, and making a developer
/// find a Settings toggle before they can see why a paint is slow would be
/// the wrong trade. In release it follows `CoreSettings.diagnosticsEnabled`
/// (Settings → Advanced), which defaults
/// to off: the surfaces poll RSS and register a frame-timings callback, and
/// a shipping app should not do either until asked.
///
/// Reads the settings snapshot without waiting on the async load — a
/// release build whose preferences have not landed yet reports `false`,
/// which is the same answer the default gives.
final Provider<bool> diagnosticsEnabledProvider = Provider<bool>((ref) {
  if (!kReleaseMode) return true;
  final settings = ref.watch(appSettingsProvider).value;
  return settings?.core.diagnosticsEnabled ?? false;
});
