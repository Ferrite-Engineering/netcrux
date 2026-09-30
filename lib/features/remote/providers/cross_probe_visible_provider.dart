// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the docked cross-probe side-panel
/// currently occupies the workspace's right pane.
///
/// App-global and ephemeral: one panel, one visibility flag shared across
/// tabs (a global provider read from a per-tab scope falls through to this
/// root instance). Deliberately NOT persisted in [AppSettings] — the panel is
/// a transient inspector surface, like the old modal dialog it replaces, not a
/// saved layout preference. Toggled by the toolbar `Icons.sensors` button, the
/// `showCrossProbePanel` action, and the panel's own close chevron. The
/// `NetcruxRightDock` lists [NetCruxCrossProbePanel] as a right-dock tab when
/// this is true, taking precedence over the inspector / analysis dock.
class CrossProbeVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Flips the panel between shown and hidden (toolbar button / action).
  void toggle() => state = !state;

  /// Sets the panel visibility explicitly (panel close chevron → false).
  // ignore: use_setters_to_change_properties
  void set({required bool visible}) => state = visible;
}

/// The docked cross-probe panel's visibility. See [CrossProbeVisibleNotifier].
final crossProbeVisibleProvider =
    NotifierProvider<CrossProbeVisibleNotifier, bool>(
      CrossProbeVisibleNotifier.new,
      name: 'crossProbeVisibleProvider',
    );
