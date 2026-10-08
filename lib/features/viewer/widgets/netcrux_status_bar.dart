// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_status_bar/crux_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/providers/status_bar_trailing_widgets_provider.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';

/// Thin status bar pinned to the bottom of each open project tab.
///
/// Shows the loaded design's identity — primary source file, top module
/// name, and the design-wide cell count — so the user always has the
/// "what am I looking at" context without opening a panel, like the status
/// bar in every other suite app.
///
/// Mounted **per-tab** (inside `ProjectTabContent`, below `NetcruxIdeLayout`)
/// rather than as outer workspace chrome, mirroring how the IDE panels are
/// mounted: every read here resolves to this tab's container, so it reads
/// [currentProjectProvider] / [loadedNetlistProvider] directly and the
/// zero-tabs empty canvas stays chrome-free.
///
/// Beyond that identity it carries two things the suite grammar puts here: a
/// zero-suppressed "Yosys not found" segment, and an elaboration busy
/// indicator in the trailing slot ahead of the Pro extension seam.
///
/// Live performance metrics (layout time + sparkline, FPS, memory) are
/// intentionally **not** here — they live in the collapsible
/// live-statistics strip (`NetcruxStatsStrip`), which docks above this bar.
class NetcruxStatusBar extends ConsumerWidget {
  /// Creates the per-tab design status bar.
  const NetcruxStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);

    final project = ref.watch(currentProjectProvider);
    final netlistAsync = ref.watch(loadedNetlistProvider);
    final netlist = netlistAsync.value;
    // Yosys resolves once per process and is `keepAlive`, so this is a cheap
    // read of an already-warm probe.
    // A build that cannot elaborate at all (the browser) never looks for
    // Yosys, so its absence there is not news.
    final yosysMissing =
        ref.watch(hdlElaborationSupportedProvider) &&
        ref
            .watch(yosysAvailabilityProvider)
            .maybeWhen(data: (a) => !a.isAvailable, orElse: () => false);

    final fileName = project.sourceFiles.isEmpty
        ? null
        : NetcruxProject.locationLabel(project.sourceFiles.first);
    final topName = netlist?.topModule?.name;
    // Design-wide cell count: sum every module definition's cell map. For a
    // hierarchical design (e.g. VexRiscv → VexRiscv + DataCache +
    // InstructionCache) this is the flattened ~total the user expects, not
    // just the top scope's direct children.
    final cellCount = netlist?.modules.values.fold<int>(
      0,
      (sum, module) => sum + module.cells.length,
    );

    final labels = <String>[
      if (fileName != null) l10n.statusBarFile(fileName),
      if (topName != null && topName.isNotEmpty)
        l10n.statusBarTopModule(topName),
      if (cellCount != null) l10n.statusBarCellCount(cellCount),
    ];

    // Adopt the shared cross-suite chrome: CruxStatusBar owns the height,
    // typography, surface, and border so NetCrux's bottom bar matches WaveCrux
    // (the canonical). NetCrux contributes only its own slots.
    return CruxStatusBar(
      segments: [
        if (labels.isEmpty)
          CruxStatusSegment(l10n.statusBarNoDesign)
        else
          for (final label in labels) CruxStatusSegment(label),
        // A missing engine is the single most common cause of an elaboration
        // that never produces a netlist. It used to be visible only in
        // Settings and the Welcome screen, so a user who got past those and
        // then hit a silent failure had nowhere to look. Zero-suppressed per
        // the suite grammar: present only when there is something wrong.
        if (yosysMissing) CruxStatusSegment(l10n.statusBarYosysUnavailable),
      ],
      // Suite grammar: progress first, then the Pro extension slot.
      trailing: [
        if (netlistAsync.isLoading)
          CruxStatusBusyIndicator(
            semanticsLabel: l10n.statusBarBusyElaborating,
          ),
        ...ref.watch(statusBarTrailingWidgetsProvider),
      ],
    );
  }

  /// The empty-canvas variant: the same chrome, an explicit idle label, and
  /// **no per-tab reads**.
  ///
  /// The bar proper is mounted inside `ProjectTabContent`, so with zero tabs
  /// there is nothing to mount it in and the window's bottom edge used to
  /// simply lose 24 dp — while WaveCrux and LintCrux kept theirs. Rather than
  /// hoist the real bar above `PaneHost` and feed it the active tab's
  /// container, which `active_tab_container.dart` documents as the cause of the
  /// "markNeedsBuild during build" crashes on launch, the empty state gets its
  /// own stateless bar. It reads nothing, so it cannot reintroduce that hazard.
  /// The Pro extension slot is carried here too. It is the ONLY provider this
  /// variant reads, and deliberately so: `statusBarTrailingWidgetsProvider` is
  /// a plain `Provider<List<Widget>>` the host overrides with a const list, so
  /// watching it cannot reach the active tab's container and cannot
  /// reintroduce the "markNeedsBuild during build" hazard described above.
  ///
  /// Without it the empty canvas would drop the edition badge the overlay
  /// mounts there: WaveCrux states the edition on its welcome screen, and a
  /// NetCrux start screen that did not would be a suite divergence with no
  /// platform reason behind it.
  static Widget idle(BuildContext context) => Consumer(
    builder: (context, ref, _) => CruxStatusBar(
      segments: [CruxStatusSegment(L10N.of(context).statusBarNoDesign)],
      trailing: ref.watch(statusBarTrailingWidgetsProvider),
    ),
  );
}
