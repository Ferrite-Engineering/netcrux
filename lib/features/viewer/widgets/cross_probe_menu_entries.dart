// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/remote/services/netcrux_cross_probe_selection.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';

/// Builds the "Cross-probe to" entry for the schematic right-click /
/// long-press context menu.
///
/// One entry, built from the shared `crossProbeMenuEntry`: the targets are the
/// connected suite products (several windows of one product as a nested
/// submenu), or, with none running, a disabled entry whose tooltip says what
/// to start. Choosing it opens the targets as a second menu where the schematic
/// menu opened, after that menu has closed.
///
/// Cross-probing is free in every edition, sending as well as receiving, so
/// the entry carries no tier chip and its tap is not gated. The peers it lists
/// are the shared, filtered list, so an organization's allowlist applies here
/// as it does to the panel and the badge.
///
/// [target] is the element the user right-clicked, which need not be the
/// selection, so the send names [target] itself.
List<SchematicContextMenuExtensionEntry> buildCrossProbeMenuEntries(
  WidgetRef ref,
  SelectedElement target,
) {
  final entry =
      crossProbeMenuEntry(
            ref.context,
            ref,
            selection: () => netcruxCrossProbeSelectionOf(ref.read, target),
          )
          as CruxSubmenu;
  return <SchematicContextMenuExtensionEntry>[
    SchematicContextMenuExtensionEntry(
      id: 'cxp-cross-probe-to',
      label: entry.label,
      tooltip: entry.tooltip,
      enabled: entry.enabled,
      onTap: (context, _, globalPosition) => showCruxContextMenu(
        context,
        globalPosition: globalPosition,
        entries: entry.entries,
      ),
    ),
  ];
}
