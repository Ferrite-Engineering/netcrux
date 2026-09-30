// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/workspace/services/pro_action_gate.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/source_pane/source_pane_openers.dart';
import 'package:netcrux/shared/widgets/netcrux_feature_tier_badge.dart';

/// Right-pane inspector showing details about the current selection.
///
/// Renders one of four states based on the active [SelectedElement]:
///
/// - none → empty message.
/// - cell → type / instance / parameters / port-binding table.
/// - port (or boundary port) → direction / width / net.
/// - wire → net name / width / driver / sinks.
class InspectorPanel extends ConsumerWidget {
  /// Creates an inspector panel.
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = L10N.of(context);
    final selection = ref.watch(selectedElementProvider);
    final tree = ref.watch(hierarchyTreeProvider);
    final laidOutAsync = ref.watch(currentLaidOutGraphProvider);
    final laidOut = laidOutAsync.value ?? LaidOutGraph.empty;
    final model = tree.model;
    final module = (model == null) ? null : tree.selected?.resolve(model);
    final primary = selection.primary;

    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // "Go to source" is offered here as well as on the schematic
            // context menu, deliberately. The Inspector is where someone
            // reading an element's details forms the question "where does this
            // come from"; making them dismiss the panel and right-click the
            // canvas to answer it is the kind of small friction that stops
            // people using a feature at all. The opener falls back to the
            // active selection, so no ElementId plumbing is needed here.
            //
            // It is the Pro RTL source pane's action, so it carries the tier
            // badge and goes through the same gate as the menu entry: an
            // open-core build says it requires NetCrux Pro rather than doing
            // nothing.
            if (primary is! SelectedElementNone)
              Row(
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () {
                      if (!allowProAction(
                        context,
                        ref,
                        NetcruxAction.openSourceForElement,
                      )) {
                        return;
                      }
                      ref.read(openSourceForElementOpenerProvider)(
                        context,
                        ref,
                      );
                    },
                    icon: const Icon(Icons.code, size: 14),
                    label: Text(
                      l10n.inspectorGoToSource,
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  NetCruxFeatureTierBadge(
                    requiredTier:
                        NetcruxAction.openSourceForElement.requiredTier,
                  ),
                ],
              ),
            Expanded(
              child: switch (primary) {
                SelectedElementNone() => CruxPanelEmptyState(
                  message: l10n.inspectorEmpty,
                ),
                SelectedElementCell(:final cellId) => _CellView(
                  cellId: cellId,
                  schematic: laidOut.graph,
                  module: module,
                ),
                SelectedElementPort(:final cellId, :final portName) =>
                  _PortView(
                    cellId: cellId,
                    portName: portName,
                    module: module,
                  ),
                SelectedElementBoundaryPort(:final portName) =>
                  _BoundaryPortView(
                    portName: portName,
                    module: module,
                  ),
                SelectedElementWire(:final edgeId, :final netId) => _WireView(
                  edgeId: edgeId,
                  netId: netId,
                  schematic: laidOut.graph,
                  module: module,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _CellView extends StatelessWidget {
  const _CellView({
    required this.cellId,
    required this.schematic,
    required this.module,
  });

  final String cellId;
  final SchematicGraph schematic;
  final Module? module;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final cell = schematic.cells.where((c) => c.id == cellId).firstOrNull;
    if (cell == null) {
      return CruxPanelEmptyState(message: l10n.inspectorEmpty);
    }
    final modCell = module?.cells[cellId];
    final children = <Widget>[
      _SectionHeader(text: l10n.inspectorCellHeader),
      _FieldRow(label: l10n.inspectorFieldInstance, value: cell.id),
      _FieldRow(label: l10n.inspectorFieldType, value: cell.type),
      _FieldRow(label: l10n.inspectorFieldKind, value: cell.kind.name),
    ];
    if (modCell != null && modCell.parameters.isNotEmpty) {
      children
        ..add(const Divider(height: 16))
        ..add(_SectionHeader(text: l10n.inspectorParametersHeader));
      for (final entry in modCell.parameters.entries) {
        children.add(_FieldRow(label: entry.key, value: entry.value));
      }
    }
    children
      ..add(const Divider(height: 16))
      ..add(_SectionHeader(text: l10n.inspectorPortsHeader));
    for (final port in cell.ports) {
      children.add(
        _FieldRow(
          label: port.name,
          value: port.direction.name,
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _PortView extends StatelessWidget {
  const _PortView({
    required this.cellId,
    required this.portName,
    required this.module,
  });

  final String cellId;
  final String portName;
  final Module? module;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final cell = module?.cells[cellId];
    final direction = cell?.portDirections[portName] ?? PortDirection.input;
    final bits = cell?.connections[portName] ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionHeader(text: l10n.inspectorPortHeader),
        _FieldRow(label: l10n.inspectorFieldInstance, value: cellId),
        _FieldRow(label: 'port', value: portName),
        _FieldRow(label: l10n.inspectorFieldDirection, value: direction.name),
        _FieldRow(label: l10n.inspectorFieldWidth, value: '${bits.length}'),
      ],
    );
  }
}

class _BoundaryPortView extends StatelessWidget {
  const _BoundaryPortView({required this.portName, required this.module});

  final String portName;
  final Module? module;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final port = module?.ports[portName];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionHeader(text: l10n.inspectorPortHeader),
        _FieldRow(label: l10n.inspectorFieldInstance, value: '(boundary)'),
        _FieldRow(label: 'port', value: portName),
        if (port != null) ...<Widget>[
          _FieldRow(
            label: l10n.inspectorFieldDirection,
            value: port.direction.name,
          ),
          _FieldRow(label: l10n.inspectorFieldWidth, value: '${port.width}'),
        ],
      ],
    );
  }
}

class _WireView extends StatelessWidget {
  const _WireView({
    required this.edgeId,
    required this.netId,
    required this.schematic,
    required this.module,
  });

  final String edgeId;
  final int netId;
  final SchematicGraph schematic;
  final Module? module;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final edge = schematic.edges.where((e) => e.id == edgeId).firstOrNull;
    if (edge == null) {
      return CruxPanelEmptyState(message: l10n.inspectorEmpty);
    }
    final sinkIds =
        schematic.edges
            .where((e) => e.netId == netId && e.id != edgeId)
            .map((e) => e.targetPortId)
            .toSet()
          ..add(edge.targetPortId);
    final m = module;
    final netName = m == null ? null : _findNetNameIn(m, netId);
    // Fixed header rows, then one row per sink. Clicking the clock net of a
    // flattened SoC selects a net whose fanout is the whole design: the
    // previous shape put every sink in one `SelectableText` inside a
    // non-scrolling `Column`, which both laid out a single N-line paragraph
    // and overflowed the pane with no way to scroll. A `ListView.builder`
    // builds only the rows in view and scrolls the rest.
    final fixed = <Widget>[
      _SectionHeader(text: l10n.inspectorWireHeader),
      if (netName != null)
        _FieldRow(label: l10n.inspectorFieldNet, value: netName),
      _FieldRow(label: l10n.inspectorFieldNetId, value: '$netId'),
      _FieldRow(label: l10n.inspectorFieldDriver, value: edge.sourcePortId),
    ];
    final sinks = sinkIds.toList(growable: false);
    return ListView.builder(
      itemCount: fixed.length + sinks.length,
      itemBuilder: (context, index) {
        if (index < fixed.length) return fixed[index];
        final sinkIndex = index - fixed.length;
        // The label column carries the "Sinks" heading on the first sink
        // only, so the stacked rows read the way the joined paragraph did.
        return _FieldRow(
          label: sinkIndex == 0 ? l10n.inspectorFieldSinks : '',
          value: sinks[sinkIndex],
        );
      },
    );
  }

  String? _findNetNameIn(Module mod, int netId) {
    for (final net in mod.nets.values) {
      for (final bit in net.bits) {
        final dyn = bit.toJson();
        if (dyn is int && dyn == netId) return net.name;
      }
    }
    return null;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
