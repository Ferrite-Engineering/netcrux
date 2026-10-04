// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The laid-out routes and the schematic graph must name every wire the same
// way. A clicked wire carries a layout id; the inspector, the trace service,
// the painter's trace highlight and Zoom to Selection look ids up on the
// other side. These checks run on captured netlists with high-fanout nets
// (clock, reset, enables), which the layout leaves unrouted while the graph
// keeps them: the case hand-built fixtures never reach.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/inspector/widgets/inspector_panel.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/features/viewer/selection/schematic_hit_test.dart';
import 'package:netcrux/features/viewer/selection/selection_bounds.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';
import 'package:netcrux/services/schematic/declared_cell_ports.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/schematic/trace_service.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

import '../../helpers/elk_ffi_library_gate.dart';

/// One scope of a captured netlist, laid out by the native engine.
class _Laid {
  _Laid(this.model, this.laidOut, this.elkEdges);

  final NetlistModel model;
  final LaidOutGraph laidOut;

  /// The ELK input's edges: id to (source port, target port).
  final Map<String, (String, String)> elkEdges;
}

NetlistModel _load(String fixture) {
  final bytes = File('test/fixtures/netlist/$fixture').readAsBytesSync();
  return const StreamingYosysJsonReader().parse(
    utf8.decode(gzip.decode(bytes)),
  );
}

/// The scope a [moduleName] instance of the top module opens, or the root
/// when [moduleName] is the top itself.
HierarchyNode _nodeFor(NetlistModel model, String moduleName) {
  final root = HierarchyNode.rootOf(model)!;
  if (root.moduleName == moduleName) return root;
  final top = model.topModule!;
  final instance = top.cells.values.firstWhere((c) => c.type == moduleName);
  return root.child(model, instance.name)!;
}

/// Builds the graph and the layout exactly as `currentLaidOutGraphProvider`
/// does: the graph from the scope, the layout from the patched module.
_Laid _layOut(String fixture, String moduleName) {
  final model = _load(fixture);
  final node = _nodeFor(model, moduleName);
  final graph = const SchematicGraphBuilder().build(model, node);
  final input = buildElkInput(
    withDeclaredCellPorts(model, node.resolve(model)!),
  );
  final elkEdges = <String, (String, String)>{
    for (final edge
        in (input['edges']! as List<Object?>).cast<Map<String, Object?>>())
      edge['id']! as String: (
        (edge['sources']! as List<Object?>).single! as String,
        (edge['targets']! as List<Object?>).single! as String,
      ),
  };
  final solver = NativeElkSolver.open();
  try {
    final layout = NetlistLayout.fromJson(
      jsonDecode(solver.solve(jsonEncode(input))) as Map<String, Object?>,
    );
    return _Laid(model, LaidOutGraph(graph: graph, layout: layout), elkEdges);
  } finally {
    solver.dispose();
  }
}

/// The host cell of a `<cell>:<port>` pin id, or null for a boundary port.
String? _hostOf(String portId) {
  if (portId.startsWith('port:')) return null;
  return portId.substring(0, portId.lastIndexOf(':'));
}

/// A design point on [route] that the hit tester resolves to that route,
/// trying the midpoint of each segment in turn.
SelectedElementWire? _clickOn(LaidOutGraph laidOut, EdgeRoute route) {
  final hitTester = SchematicHitTester(
    laidOut: laidOut,
    transform: ViewportTransform.identity,
  );
  for (var i = 0; i + 1 < route.points.length; i++) {
    final a = route.points[i];
    final b = route.points[i + 1];
    final hit = hitTester.hitTest(
      Offset((a.x + b.x) / 2, (a.y + b.y) / 2),
    );
    if (hit is SelectedElementWire && hit.edgeId == route.id) return hit;
  }
  return null;
}

void _expectIdsAgree(_Laid laid) {
  final graphEdges = {for (final e in laid.laidOut.graph.edges) e.id: e};
  final routes = laid.laidOut.layout.edges;
  expect(routes, isNotEmpty);
  final mismatched = <String>[];
  for (final route in routes) {
    final graphEdge = graphEdges[route.id];
    final (source, target) = laid.elkEdges[route.id]!;
    if (graphEdge == null ||
        graphEdge.sourcePortId != source ||
        graphEdge.targetPortId != target) {
      mismatched.add(
        '${route.id}: layout $source -> $target, graph '
        '${graphEdge == null ? 'missing' : '${graphEdge.sourcePortId} -> '
                  '${graphEdge.targetPortId}'}',
      );
    }
  }
  expect(
    mismatched,
    isEmpty,
    reason:
        '${mismatched.length} of ${routes.length} routed edges disagree:\n'
        '${mismatched.take(5).join('\n')}',
  );
}

/// A cell's trace lights exactly the routed edges that reach its pins in the
/// traced direction, and Zoom to Selection frames that neighbourhood.
void _expectCellTraceLocal(_Laid laid, String cellId) {
  final laidOut = laid.laidOut;
  final routedIds = {for (final r in laidOut.layout.edges) r.id};
  final graphIds = {for (final e in laidOut.graph.edges) e.id};
  for (final mode in TraceOverlayMode.values) {
    final overlay = const TraceService().compute(
      laidOut: laidOut,
      selection: SelectedElement.cell(cellId: cellId),
      mode: mode,
    );
    final expected = <String>{
      for (final entry in laid.elkEdges.entries)
        if (routedIds.contains(entry.key) &&
            _hostOf(
                  mode == TraceOverlayMode.fanin
                      ? entry.value.$2
                      : entry.value.$1,
                ) ==
                cellId)
          entry.key,
    };
    expect(expected, isNotEmpty, reason: '$cellId $mode');
    expect(
      overlay.highlightedEdgeIds.where(routedIds.contains).toSet(),
      expected,
      reason: '$cellId $mode',
    );
    expect(graphIds.containsAll(overlay.highlightedEdgeIds), isTrue);
    // Every lit cell is a drawn cell: a Yosys cell name carries colons
    // (`$and$alu.v:42$7`), so the host of a pin is cut at its last colon.
    for (final id in overlay.highlightedCellIds) {
      expect(laidOut.layout.findNode(id), isNotNull, reason: '$cellId $mode');
    }

    final bounds = selectionBounds(
      laidOut,
      selection: <SelectedElement>[SelectedElement.cell(cellId: cellId)],
      overlay: overlay,
    )!;
    final cells = BoundingBox.encompass(<BoundingBox>[
      for (final id in <String>{
        ...overlay.highlightedCellIds,
        ...overlay.highlightedBoundaryPortIds,
      })
        if (laidOut.layout.findNode(id) case final node?) node.bounds,
    ])!;
    // The routes between the lit elements may bow out past their boxes,
    // but not by a large fraction of the design.
    final design = laidOut.layout.bounds;
    final slackX = 0.1 * design.width;
    final slackY = 0.1 * design.height;
    expect(
      bounds.x >= cells.x - slackX &&
          bounds.y >= cells.y - slackY &&
          bounds.x + bounds.width <= cells.x + cells.width + slackX &&
          bounds.y + bounds.height <= cells.y + cells.height + slackY,
      isTrue,
      reason:
          '$cellId $mode: framed $bounds for lit cells $cells in a '
          '$design design',
    );
  }
}

Future<void> _expectInspectorResolves(
  WidgetTester tester,
  LaidOutGraph laidOut,
  SelectedElementWire wire,
) async {
  final container = ProviderContainer(
    overrides: [
      currentLaidOutGraphProvider.overrideWith((ref) async => laidOut),
    ],
  );
  addTearDown(container.dispose);
  container.read(selectedElementProvider.notifier).select(wire);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: 320, height: 600, child: InspectorPanel()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('No selection'), findsNothing);
  expect(find.text('Wire'), findsOneWidget);
  final edge = laidOut.graph.findEdge(wire.edgeId)!;
  expect(find.text(edge.sourcePortId), findsOneWidget);
}

void main() {
  group('serv_ice40 service', () {
    const lut = 'servant.servile.cpu.alu.add_cy_r_SB_LUT4_I3_1';
    _Laid? laid;
    _Laid laidOut() => laid ??= _layOut(
      'serv_ice40/captured/serv_ice40.netlist.json.gz',
      'service',
    );

    test('every routed edge has the same id and endpoints in the graph', () {
      if (!requireElkFfiLibrary()) return;
      _expectIdsAgree(laidOut());
    });

    testWidgets('clicking the I3 wire of the carry LUT resolves everywhere', (
      tester,
    ) async {
      if (!requireElkFfiLibrary()) return;
      final l = laidOut();
      final route = l.laidOut.layout.edges.firstWhere(
        (r) => l.elkEdges[r.id]!.$2 == '$lut:I3',
      );
      final wire = _clickOn(l.laidOut, route);
      expect(wire, isNotNull, reason: 'no point on ${route.id} hits it');
      expect(wire!.netId, 576);

      await _expectInspectorResolves(tester, l.laidOut, wire);

      final fanin = const TraceService().compute(
        laidOut: l.laidOut,
        selection: wire,
        mode: TraceOverlayMode.fanin,
      );
      expect(fanin.highlightedEdgeIds, contains(route.id));
      final driver = _hostOf(
        l.laidOut.graph.findEdge(wire.edgeId)!.sourcePortId,
      );
      expect(fanin.highlightedCellIds, containsAll(<String?>[driver, lut]));
      final driverType = l.model.modules['service']!.cells[driver]!.type;
      expect(driverType, startsWith('SB_DFF'));
    });

    test('a cell trace lights its own routed edges and frames locally', () {
      if (!requireElkFfiLibrary()) return;
      _expectCellTraceLocal(laidOut(), lut);
    });
  });

  group('vexriscv DataCache', () {
    _Laid? laid;
    _Laid laidOut() => laid ??= _layOut(
      'vexriscv/captured/vexriscv.netlist.json.gz',
      'DataCache',
    );

    test('every routed edge has the same id and endpoints in the graph', () {
      if (!requireElkFfiLibrary()) return;
      _expectIdsAgree(laidOut());
    });

    testWidgets('a clicked wire resolves in the inspector and the trace', (
      tester,
    ) async {
      if (!requireElkFfiLibrary()) return;
      final l = laidOut();
      // From the end of the edge order, past the high-fanout nets the
      // layout leaves unrouted.
      SelectedElementWire? wire;
      for (final route in l.laidOut.layout.edges.reversed) {
        if (_hostOf(l.elkEdges[route.id]!.$1) == null) continue;
        wire = _clickOn(l.laidOut, route);
        if (wire != null) break;
      }
      expect(wire, isNotNull);
      await _expectInspectorResolves(tester, l.laidOut, wire!);
      final fanin = const TraceService().compute(
        laidOut: l.laidOut,
        selection: wire,
        mode: TraceOverlayMode.fanin,
      );
      expect(fanin.highlightedEdgeIds, contains(wire.edgeId));
      expect(fanin.highlightedCellIds, isNotEmpty);
    });

    test('a cell trace lights its own routed edges and frames locally', () {
      if (!requireElkFfiLibrary()) return;
      final l = laidOut();
      // A cell with routed edges on both sides, late in the edge order.
      final routedIds = {
        for (final r in l.laidOut.layout.edges.reversed) r.id,
      };
      final sources = <String?>{
        for (final id in routedIds) _hostOf(l.elkEdges[id]!.$1),
      };
      final cell = <String?>{
        for (final id in routedIds) _hostOf(l.elkEdges[id]!.$2),
      }.firstWhere((c) => c != null && sources.contains(c))!;
      _expectCellTraceLocal(l, cell);
    });
  });
}
