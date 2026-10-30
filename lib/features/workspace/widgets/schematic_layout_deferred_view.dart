// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_stats_strip/crux_stats_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/schematic/scope_layout_gate.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/providers/layout_approval_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/services/cone_view_controller.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/schematic/net_name_lookup.dart';

/// Shown in place of the schematic when the selected scope holds more cells
/// than the layout limit and nobody has asked for it to be laid out.
///
/// Nothing has failed and nothing is running: the view says how large the
/// scope is, names the way forward that needs no whole-scope layout (find a
/// cell with Search or the Hierarchy filter: selecting it opens its Cone
/// View), and offers "Lay out anyway" with the memory the layout is estimated
/// to need. The Hierarchy panel, Search, the Inspector and Cone View all work
/// while it is on show.
///
/// A selection normally opens its cone at once, so this view is not on show
/// with something selected. It is after Show Whole Scope, which leaves the
/// cone and keeps the selection: the view then names what is selected and
/// offers "Show Cone View" to open its cone again.
class SchematicLayoutDeferredView extends ConsumerWidget {
  /// Creates the view for [gate], the decision for the scope on the canvas.
  const SchematicLayoutDeferredView({required this.gate, super.key});

  /// Widget key of the "Lay out anyway" button, so tests can drive it
  /// locale-independently.
  static const Key layOutAnywayKey = Key('schematicLayoutDeferredLayOut');

  /// Widget key of the "Show Cone View" button, shown while something is
  /// selected.
  static const Key showConeKey = Key('schematicLayoutDeferredShowCone');

  /// The size decision this view reports.
  final ScopeLayoutGate gate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final scope = ref.watch(hierarchyTreeProvider).selected;
    final selected = ref.watch(selectedElementProvider).primary;
    final model = ref.watch(loadedNetlistProvider).value;
    final module = scope == null || model == null ? null : scope.resolve(model);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  l10n.schematicLayoutDeferredTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.schematicLayoutDeferredBody(
                  scope?.displayName ?? '',
                  gate.cellCount,
                  gate.limit,
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.schematicLayoutDeferredCone,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (!selected.isNone) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  l10n.schematicLayoutDeferredSelected(
                    _selectionLabel(selected, module),
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: showConeKey,
                  onPressed: () => ConeViewController(ref.read).enter(),
                  child: Text(l10n.schematicLayoutDeferredShowCone),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: layOutAnywayKey,
                onPressed: scope == null
                    ? null
                    : () => ref
                          .read(layoutApprovalProvider.notifier)
                          .approve(
                            scope,
                          ),
                child: Text(l10n.schematicLayoutDeferredAction),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.schematicLayoutDeferredEstimate(
                  formatLayoutMemoryEstimate(gate.estimatedBytes),
                ),
                textAlign: TextAlign.center,
                style: secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The name the view gives the selected [element]: the cell, the pin, the
/// boundary port, or the wire's net in [module] (its edge id when unnamed).
String _selectionLabel(SelectedElement element, Module? module) {
  switch (element) {
    case SelectedElementNone():
      return '';
    case SelectedElementCell(:final cellId):
      return cellId;
    case SelectedElementPort(:final portId):
      return portId;
    case SelectedElementBoundaryPort(:final portName):
      return portName;
    case SelectedElementWire(:final edgeId, :final netId):
      return netNameForId(module, netId) ?? edgeId;
  }
}

/// [bytes] as a rounded figure for the layout estimate: tenths of a gigabyte
/// below 10 GB, whole gigabytes above, since the estimate is no more precise
/// than that.
String formatLayoutMemoryEstimate(int bytes) {
  const gigabyte = 1024 * 1024 * 1024;
  if (bytes < 10 * gigabyte) return cruxFormatBytes(bytes);
  return '${(bytes / gigabyte).round()} GB';
}
