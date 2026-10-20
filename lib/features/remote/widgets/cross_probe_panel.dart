// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/remote/providers/cross_probe_visible_provider.dart';
import 'package:netcrux/features/remote/services/netcrux_cross_probe_selection.dart';

/// NetCrux's docked cross-probe panel.
///
/// The shared `CruxCrossProbePanel`, bound to the shared CXP lifecycle (the
/// peers, the unreachable peers and the event log) with the two things that
/// are NetCrux's own: how to read the current selection, and how to close the
/// panel. `NetcruxRightDock` lists it as a right-dock tab when
/// `crossProbeVisibleProvider` is set.
///
/// Mounted inside the active tab's provider scope (the right pane of the
/// per-tab IDE layout), so the selection resolves this tab's
/// `selectedElementProvider` / `hierarchyTreeProvider` / `currentProjectProvider`
/// directly, while the root-scoped CXP providers resolve through the parent.
class NetCruxCrossProbePanel extends ConsumerWidget {
  /// Creates the docked cross-probe panel.
  const NetCruxCrossProbePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CruxCrossProbePanel(
      // Docked as a CruxDock tab: the strip already carries the icon, the
      // label and the close button, so the panel's own header would duplicate
      // all three directly underneath.
      selection: () => netcruxCrossProbeSelection(ref.read),
      onClose: () =>
          ref.read(crossProbeVisibleProvider.notifier).set(visible: false),
    );
  }
}
