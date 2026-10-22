// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/remote/services/netcrux_cross_probe_selection.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Builds the "Cross-probe to" entry for the schematic right-click /
/// long-press context menu, and, on a register, "Show timing paths through
/// this register" beside it.
///
/// "Cross-probe to" is built from the shared `crossProbeMenuEntry`: the
/// targets are the connected suite products (several windows of one product
/// as a nested submenu), or, with none running, a disabled entry whose
/// tooltip says what to start. Choosing it opens the targets as a second menu
/// where the schematic menu opened, after that menu has closed.
///
/// "Show timing paths through this register" sends SimCrux the register's
/// RTL name as a `signal` ([netcruxRegisterSignalSelectionOf]) through the
/// same shared send, and SimCrux filters its worst paths to those through
/// it. Without a SimCrux running it stays on the menu, disabled, with a
/// tooltip saying what to start.
///
/// Cross-probing is free in every edition, sending as well as receiving, so
/// neither entry carries a tier chip and neither tap is gated. The peers they
/// list are the shared, filtered list, so an organization's allowlist applies
/// here as it does to the panel and the badge.
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
    ?_timingPathsEntry(ref, target),
  ];
}

/// The wire name of the product that shows timing paths.
const String _kSimcrux = 'simcrux';

SchematicContextMenuExtensionEntry? _timingPathsEntry(
  WidgetRef ref,
  SelectedElement target,
) {
  if (target is! SelectedElementCell) return null;
  final cellId = target.cellId;
  // Only a register has paths through it; anything else gets no entry.
  if (netcruxRegisterSignalSelectionOf(ref.read, cellId) == null) return null;
  final l10n = L10N.of(ref.context);
  final simcrux = ref
      .read(crossProbeTargetsProvider)
      .where((t) => t.productName.toLowerCase() == _kSimcrux)
      .firstOrNull;
  return SchematicContextMenuExtensionEntry(
    id: 'cxp-show-timing-paths',
    label: l10n.menuShowTimingPathsThroughRegister,
    enabled: simcrux != null,
    tooltip: simcrux == null ? l10n.menuShowTimingPathsNeedsSimcrux : null,
    onTap: (context, ref, globalPosition) async {
      if (simcrux == null) return;
      // Resolved when chosen, against the tab the menu opened in.
      final selection = netcruxRegisterSignalSelectionOf(ref.read, cellId);
      if (!simcrux.hasSeveralInstances) {
        await sendCrossProbe(
          context,
          ref,
          peer: simcrux.instances.single,
          selection: selection,
          label: simcrux.label,
        );
        return;
      }
      // Several SimCrux windows: the user picks one, where the menu was.
      final strings = cruxCxpStringsOf(context, ref.read);
      await showCruxContextMenu(
        context,
        globalPosition: globalPosition,
        entries: <CruxMenuEntry>[
          for (var i = 0; i < simcrux.instances.length; i++)
            CruxMenuItem(
              key: ValueKey<String>(
                'timingPathsTarget:${simcrux.instances[i].peerId}',
              ),
              label: _instanceLabel(strings, simcrux, i),
              onSelected: () => unawaited(
                sendCrossProbe(
                  context,
                  ref,
                  peer: simcrux.instances[i],
                  selection: selection,
                  label: simcrux.label,
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// "SimCrux 2", or "SimCrux 2 (alu.v)" when that window announces its
/// design, in the shared cross-probe wording. Display text only.
String _instanceLabel(
  CruxCxpStrings strings,
  CrossProbeTarget target,
  int index,
) {
  final instance = strings.instanceLabel(target.label, index + 1);
  final document = target.instances[index].activeDocument;
  return document == null
      ? instance
      : strings.instanceDocumentLabel(instance, document);
}
