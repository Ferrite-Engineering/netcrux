// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/inspector/providers/inspector_providers.dart';
import 'package:netcrux/features/inspector/providers/received_timing_path_provider.dart';
import 'package:netcrux/features/inspector/services/pin_tie_text.dart';
import 'package:netcrux/features/inspector/widgets/annotation_inspector_section.dart';
import 'package:netcrux/features/inspector/widgets/timing_path_inspector_section.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/schematic_canvas_key_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/workspace/services/pro_action_gate.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/custom_cell_symbols/custom_cell_symbol_openers.dart';
import 'package:netcrux/services/source_pane/source_pane_openers.dart';
import 'package:netcrux/shared/widgets/netcrux_feature_tier_badge.dart';

/// The right dock's Inspector: the properties of the schematic's primary
/// selection, on the shared [CruxInspector].
///
/// - cell: instance, type, kind, parameters and the port-binding table, each
///   pin with what it is tied to;
/// - port: direction, width and what it is tied to; boundary port: direction
///   and width;
/// - wire: net, driver and every sink (built lazily: the clock net of a
///   flattened SoC selects the whole design);
/// - then the Pro overlay's sections ([proInspectorSectionsProvider]), and
///   the element's annotations, editable in place.
///
/// Mounted inside the tab's provider scope, so it reads and writes that
/// tab's selection, annotations and drafts. The schematic's *Properties*
/// entry, `View > Properties` and its shortcut open it with focus
/// ([inspectorControllerProvider]); Escape returns focus to the canvas, and
/// a second Escape there clears the selection. Double-click on a cell is not
/// an opener: it pushes into the cell's module.
class InspectorPanel extends ConsumerWidget {
  /// Creates an inspector panel.
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = L10N.of(context);
    final primary = ref.watch(selectedElementProvider).primary;
    final tree = ref.watch(hierarchyTreeProvider);
    final laidOut =
        ref.watch(currentLaidOutGraphProvider).value ?? LaidOutGraph.empty;
    final model = tree.model;
    final module = (model == null) ? null : tree.selected?.resolve(model);
    final schematic = laidOut.graph;
    final overlayInstalled = ref.watch(proOverlayInstalledProvider);
    final pro = ref.watch(proInspectorSectionsProvider);

    bool resolves(SelectedElement element) => switch (element) {
      SelectedElementNone() => false,
      SelectedElementCell(:final cellId) => schematic.cells.any(
        (c) => c.id == cellId,
      ),
      SelectedElementPort(:final cellId) =>
        module?.cells[cellId] != null ||
            schematic.cells.any((c) => c.id == cellId),
      SelectedElementBoundaryPort() => true,
      SelectedElementWire(:final edgeId) => schematic.edges.any(
        (e) => e.id == edgeId,
      ),
    };

    final timingPath = ref.watch(receivedTimingPathProvider) != null;
    final inspector = CruxInspector<SelectedElement>(
      selection: primary is SelectedElementNone ? null : primary,
      controller: ref.watch(inspectorControllerProvider),
      onEscape: () =>
          focusSchematicCanvas(ref.read(schematicCanvasKeyProvider)),
      emptyMessage: l10n.inspectorEmpty,
      title: (element) => inspectorHeading(l10n, element),
      heldMessage: (element) =>
          l10n.inspectorHeldMessage(inspectorHeading(l10n, element)),
      // "Go to source" is offered here as well as on the schematic context
      // menu: the Inspector is where someone reading an element's details
      // asks where it comes from. It is the Pro RTL source pane's action,
      // so it carries the tier badge and goes through the same gate as the
      // menu entry; the opener falls back to the active selection.
      headerActions: (context, element) => <Widget>[
        TextButton.icon(
          onPressed: () {
            if (!allowProAction(
              context,
              ref,
              NetcruxAction.openSourceForElement,
            )) {
              return;
            }
            ref.read(openSourceForElementOpenerProvider)(context, ref);
          },
          icon: const Icon(Icons.code, size: 14),
          label: Text(l10n.inspectorGoToSource),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
        ),
        const SizedBox(width: 4),
        NetCruxFeatureTierBadge(
          requiredTier: NetcruxAction.openSourceForElement.requiredTier,
        ),
      ],
      sections: <CruxInspectorSectionBuilder<SelectedElement>>[
        (context, element) => switch (element) {
          SelectedElementCell(:final cellId) => _cellSection(
            context,
            ref,
            l10n,
            schematic,
            module,
            cellId,
            offerSymbolEditor: !overlayInstalled,
          ),
          SelectedElementPort(:final cellId, :final portName) => _portSection(
            l10n,
            schematic,
            module,
            cellId,
            portName,
          ),
          SelectedElementBoundaryPort(:final portName) => _boundaryPortSection(
            l10n,
            module,
            portName,
          ),
          SelectedElementWire() || SelectedElementNone() => null,
        },
        (context, element) => element is SelectedElementCell
            ? _parametersSection(l10n, module, element.cellId)
            : null,
        (context, element) => element is SelectedElementCell
            ? _portsSection(l10n, schematic, module, element.cellId)
            : null,
        (context, element) => element is SelectedElementWire
            ? _wireSection(l10n, schematic, module, element)
            : null,
        ...pro,
        (context, element) => resolves(element)
            ? AnnotationInspectorSection(element: element)
            : null,
      ],
    );
    return Material(
      color: theme.colorScheme.surface,
      // A timing path a peer sent sits above the selection's sections, so
      // it reads the same whatever is selected; bounded, so a long path
      // never pushes the selection's details off the panel.
      child: timingPath
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: const SingleChildScrollView(
                    child: TimingPathInspectorSection(),
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: inspector),
              ],
            )
          : inspector,
    );
  }
}

/// The Inspector's heading for [element]: its kind and canvas id.
String inspectorHeading(L10N l10n, SelectedElement element) =>
    switch (element) {
      SelectedElementNone() => l10n.inspectorEmpty,
      SelectedElementCell(:final cellId) => l10n.inspectorHeading(
        l10n.inspectorCellHeader,
        cellId,
      ),
      SelectedElementPort(:final portId) => l10n.inspectorHeading(
        l10n.inspectorPortHeader,
        portId,
      ),
      SelectedElementBoundaryPort(:final portName) => l10n.inspectorHeading(
        l10n.inspectorPortHeader,
        portName,
      ),
      SelectedElementWire(:final edgeId) => l10n.inspectorHeading(
        l10n.inspectorWireHeader,
        edgeId,
      ),
    };

Widget? _cellSection(
  BuildContext context,
  WidgetRef ref,
  L10N l10n,
  SchematicGraph schematic,
  Module? module,
  String cellId, {
  required bool offerSymbolEditor,
}) {
  final cell = schematic.cells.where((c) => c.id == cellId).firstOrNull;
  if (cell == null) return null;
  return CruxInspectorSection(
    title: l10n.inspectorCellHeader,
    children: <Widget>[
      CruxInspectorValueRow(label: l10n.inspectorFieldInstance, value: cell.id),
      CruxInspectorValueRow(label: l10n.inspectorFieldType, value: cell.type),
      CruxInspectorValueRow(
        label: l10n.inspectorFieldKind,
        value: cell.kind.name,
      ),
      // The module type's custom symbol is a Pro capability. A build with the
      // overlay shows its own "Custom symbol" section; without it the entry
      // stays here, badged, and its gate says what unlocks it.
      if (offerSymbolEditor)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: TextButton(
                  key: const ValueKey<String>('inspectorEditSymbol'),
                  onPressed: () {
                    if (!allowProAction(
                      context,
                      ref,
                      NetcruxAction.editSymbolForCurrentInstance,
                    )) {
                      return;
                    }
                    ref.read(editSymbolForCurrentInstanceOpenerProvider)(
                      context,
                      ref,
                      moduleType: cell.type,
                    );
                  },
                  child: Text(
                    NetcruxAction.editSymbolForCurrentInstance.label(l10n),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              NetCruxFeatureTierBadge(
                requiredTier:
                    NetcruxAction.editSymbolForCurrentInstance.requiredTier,
              ),
            ],
          ),
        ),
    ],
  );
}

Widget? _parametersSection(L10N l10n, Module? module, String cellId) {
  final parameters = module?.cells[cellId]?.parameters;
  if (parameters == null || parameters.isEmpty) return null;
  return CruxInspectorSection(
    title: l10n.inspectorParametersHeader,
    children: <Widget>[
      for (final entry in parameters.entries)
        CruxInspectorValueRow(label: entry.key, value: entry.value),
    ],
  );
}

Widget? _portsSection(
  L10N l10n,
  SchematicGraph schematic,
  Module? module,
  String cellId,
) {
  final cell = schematic.cells.where((c) => c.id == cellId).firstOrNull;
  if (cell == null) return null;
  final modCell = module?.cells[cellId];
  return CruxInspectorListSection(
    title: l10n.inspectorPortsHeader,
    itemCount: cell.ports.length,
    itemBuilder: (context, index) {
      final port = cell.ports[index];
      final tie = pinTieText(
        l10n,
        port.tie,
        modCell?.connections[port.name] ?? const <BitRef>[],
        module,
      );
      return CruxInspectorValueRow(
        label: port.name,
        value: l10n.inspectorPortWithTie(port.direction.name, tie),
      );
    },
  );
}

Widget? _portSection(
  L10N l10n,
  SchematicGraph schematic,
  Module? module,
  String cellId,
  String portName,
) {
  final cell = module?.cells[cellId];
  final bits = cell?.connections[portName] ?? const <BitRef>[];
  // The drawn pin carries the tie, and the direction of a declared port the
  // netlist left out of `connections`, which the raw cell lacks.
  final drawn = schematic.cells
      .where((c) => c.id == cellId)
      .firstOrNull
      ?.ports
      .where((p) => p.name == portName)
      .firstOrNull;
  if (cell == null && drawn == null) return null;
  final direction =
      cell?.portDirections[portName] ?? drawn?.direction ?? PortDirection.input;
  return CruxInspectorSection(
    title: l10n.inspectorPortHeader,
    children: <Widget>[
      CruxInspectorValueRow(label: l10n.inspectorFieldInstance, value: cellId),
      CruxInspectorValueRow(label: 'port', value: portName),
      CruxInspectorValueRow(
        label: l10n.inspectorFieldDirection,
        value: direction.name,
      ),
      CruxInspectorValueRow(
        label: l10n.inspectorFieldWidth,
        value: '${bits.length}',
      ),
      if (drawn != null)
        CruxInspectorValueRow(
          label: l10n.inspectorFieldTiedTo,
          value: pinTieText(l10n, drawn.tie, bits, module),
        ),
    ],
  );
}

Widget _boundaryPortSection(L10N l10n, Module? module, String portName) {
  final port = module?.ports[portName];
  return CruxInspectorSection(
    title: l10n.inspectorPortHeader,
    children: <Widget>[
      CruxInspectorValueRow(
        label: l10n.inspectorFieldInstance,
        value: '(boundary)',
      ),
      CruxInspectorValueRow(label: 'port', value: portName),
      if (port != null) ...<Widget>[
        CruxInspectorValueRow(
          label: l10n.inspectorFieldDirection,
          value: port.direction.name,
        ),
        CruxInspectorValueRow(
          label: l10n.inspectorFieldWidth,
          value: '${port.width}',
        ),
      ],
    ],
  );
}

/// The wire: its net, driver and sinks, one row per sink. The rows are a
/// [CruxInspectorListSection], so only the rows in view are built: clicking
/// the clock net of a flattened SoC selects a net whose fanout is the whole
/// design.
Widget? _wireSection(
  L10N l10n,
  SchematicGraph schematic,
  Module? module,
  SelectedElementWire wire,
) {
  final edge = schematic.edges.where((e) => e.id == wire.edgeId).firstOrNull;
  if (edge == null) return null;
  final sinkIds =
      schematic.edges
          .where((e) => e.netId == wire.netId && e.id != wire.edgeId)
          .map((e) => e.targetPortId)
          .toSet()
        ..add(edge.targetPortId);
  final netName = module == null ? null : _netNameIn(module, wire.netId);
  final fixed = <Widget>[
    if (netName != null)
      CruxInspectorValueRow(label: l10n.inspectorFieldNet, value: netName),
    CruxInspectorValueRow(
      label: l10n.inspectorFieldNetId,
      value: '${wire.netId}',
    ),
    CruxInspectorValueRow(
      label: l10n.inspectorFieldDriver,
      value: edge.sourcePortId,
    ),
  ];
  final sinks = sinkIds.toList(growable: false);
  return CruxInspectorListSection(
    title: l10n.inspectorWireHeader,
    itemCount: fixed.length + sinks.length,
    itemBuilder: (context, index) {
      if (index < fixed.length) return fixed[index];
      final sinkIndex = index - fixed.length;
      // The label column names the sinks on the first one only, so the
      // stacked rows read as one list.
      return CruxInspectorValueRow(
        label: sinkIndex == 0 ? l10n.inspectorFieldSinks : '',
        value: sinks[sinkIndex],
      );
    },
  );
}

String? _netNameIn(Module mod, int netId) {
  for (final net in mod.nets.values) {
    for (final bit in net.bits) {
      final dyn = bit.toJson();
      if (dyn is int && dyn == netId) return net.name;
    }
  }
  return null;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
