// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the docked X-trace result panel currently occupies one of the
/// workspace's dock regions.
///
/// App-global and ephemeral, exactly like [`crossProbeVisibleProvider`]: one
/// panel, one visibility flag shared across tabs (a global provider read from
/// a per-tab scope falls through to this root instance). Deliberately NOT
/// persisted in `AppSettings` — the panel is a transient inspector surface,
/// not a saved layout preference.
///
/// **Presence is this flag, never `!xTraceResult.isEmpty`.** The panel has to
/// be able to be open *and* empty, because that is the state
/// `xTracePanelEmpty` describes — "No active X-trace. Select a net and run
/// 'Show X-Trace'." — and a panel keyed on having a result could never render
/// it. That separation is also why `showXTracePanel` is a distinct action from
/// `showXTrace`, and why the tab's `×` (which clears this flag) means
/// something different from the strip's Clear button (which clears the
/// result): closing keeps the chain, so reopening restores it.
///
/// Contrast WaveCrux, whose X-Trace dock entry keys presence on `isActive` and
/// whose `onClose` therefore clears the trace. NetCrux's strings rule that
/// shortcut out.
class XTracePanelVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Flips the panel between shown and hidden (`showXTracePanel`).
  void toggle() => state = !state;

  /// Sets the panel visibility explicitly (the dock tab's `×` → false; a
  /// completed `showXTrace` walk → true).
  // ignore: use_setters_to_change_properties
  void set({required bool visible}) => state = visible;
}

/// The docked X-trace panel's visibility. See [XTracePanelVisibleNotifier].
final xTracePanelVisibleProvider =
    NotifierProvider<XTracePanelVisibleNotifier, bool>(
      XTracePanelVisibleNotifier.new,
      name: 'xTracePanelVisibleProvider',
    );
