// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/services/cone_view_controller.dart';
import 'package:netcrux/services/telemetry/telemetry_event_catalog.dart';

class _RecordingTelemetry implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);
}

const _wire = SchematicEdge(
  id: 'e_7_0',
  sourcePortId: 'u_drv:Y',
  targetPortId: 'u_load:A',
  netId: 7,
);

void main() {
  late ProviderContainer container;
  late _RecordingTelemetry telemetry;
  late ConeViewController controller;

  setUp(() {
    telemetry = _RecordingTelemetry();
    final model = NetlistModel.fromJson(
      jsonDecode(
            File(
              'test/fixtures/verilog/large_chain.expected.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>,
    );
    container = ProviderContainer(
      overrides: [
        telemetryServiceProvider.overrideWithValue(telemetry),
        currentLaidOutGraphProvider.overrideWith(
          (ref) async => const LaidOutGraph(
            graph: SchematicGraph(
              moduleName: 'large_chain',
              cells: <SchematicCell>[],
              boundaryPorts: <SchematicBoundaryPort>[],
              edges: <SchematicEdge>[_wire],
            ),
            layout: NetlistLayout(
              nodes: <NodePosition>[],
              edges: <EdgeRoute>[],
              bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(hierarchyTreeProvider.notifier).setModel(model);
    final sub = container.listen<ConeViewRequest?>(
      coneViewProvider,
      (previous, next) {},
    );
    addTearDown(sub.close);
    controller = ConeViewController(container.read);
  });

  ConeViewRequest? shown() => container.read(coneViewProvider);

  test('with nothing selected and no cone on show, nothing happens', () {
    expect(controller.enter(), isFalse);
    expect(shown(), isNull);
    expect(telemetry.events, isEmpty);
  });

  test('enters from the selection at the default depth, fan-in', () {
    container
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'u_inv_4'));
    container
        .read(traceOverlayProvider.notifier)
        .set(
          const TraceOverlay(
            mode: TraceOverlayMode.fanin,
            highlightedCellIds: <String>{'u_inv_4'},
            highlightedEdgeIds: <String>{},
            highlightedBoundaryPortIds: <String>{},
          ),
        );
    expect(controller.enter(), isTrue);
    expect(shown()?.root, const SelectedElement.cell(cellId: 'u_inv_4'));
    expect(shown()?.depth, kDefaultConeViewDepth);
    expect(shown()?.direction, ConeViewDirection.fanIn);
    expect(shown()?.scope, container.read(hierarchyTreeProvider).selected);
    expect(container.read(traceOverlayProvider).isEmpty, isTrue);
  });

  test('a given root wins over the selection and becomes it', () {
    container
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'u_inv_4'));
    controller.enter(root: const SelectedElement.cell(cellId: 'u_inv_9'));
    expect(shown()?.root, const SelectedElement.cell(cellId: 'u_inv_9'));
    expect(
      container.read(selectedElementProvider).primary,
      const SelectedElement.cell(cellId: 'u_inv_9'),
    );
  });

  test('a new cone keeps the direction and depth of the one on show', () {
    controller
      ..enter(root: const SelectedElement.cell(cellId: 'u_inv_4'))
      ..setDirection(ConeViewDirection.fanInAndFanOut)
      ..setDepth(6)
      ..enter(root: const SelectedElement.cell(cellId: 'u_inv_9'));
    expect(shown()?.direction, ConeViewDirection.fanInAndFanOut);
    expect(shown()?.depth, 6);
  });

  test('every level keeps the root on show when nothing is selected', () {
    controller.enter(root: const SelectedElement.cell(cellId: 'u_inv_4'));
    container.read(selectedElementProvider.notifier).clear();
    expect(controller.enter(transitive: true), isTrue);
    expect(shown()?.root, const SelectedElement.cell(cellId: 'u_inv_4'));
    expect(shown()?.isTransitive, isTrue);
    // Back to a limited cone: the default depth, not "every level".
    controller.enter();
    expect(shown()?.depth, kDefaultConeViewDepth);
  });

  test('records cone_view.opened with closed-vocabulary properties', () {
    controller
      ..enter(root: const SelectedElement.cell(cellId: 'u_inv_4'))
      ..enter(transitive: true);
    expect(telemetry.events.map((e) => e.name), <String>[
      'cone_view.opened',
      'cone_view.opened',
    ]);
    expect(telemetry.events.first.properties, <String, Object?>{
      'direction': 'fan_in',
      'form': 'limited',
    });
    expect(telemetry.events.last.properties['form'], 'transitive');
    final entry = kNetcruxEventCatalog.firstWhere(
      (e) => e.name == 'cone_view.opened',
    );
    for (final event in telemetry.events) {
      event.properties.forEach((key, value) {
        expect(entry.enumeratedValues[key], contains(value));
      });
    }
    for (final direction in ConeViewDirection.values) {
      expect(
        entry.enumeratedValues['direction'],
        contains(telemetryEnumToken(direction)),
      );
    }
    // The root is design IP and never leaves the machine.
    expect(telemetry.events.toString(), isNot(contains('u_inv_4')));
  });

  test('exit shows the whole scope and frames the root', () async {
    await container.read(currentLaidOutGraphProvider.future);
    controller
      ..enter(root: const SelectedElement.cell(cellId: 'u_inv_4'))
      ..exit();
    expect(shown(), isNull);
    expect(container.read(revealRequestProvider), 'u_inv_4');
    expect(
      container.read(selectedElementProvider).primary,
      const SelectedElement.cell(cellId: 'u_inv_4'),
    );
  });

  test('exit leaves a pending reveal alone', () {
    controller.enter(root: const SelectedElement.cell(cellId: 'u_inv_4'));
    container.read(revealRequestProvider.notifier).request('u_inv_20');
    controller.exit();
    expect(container.read(revealRequestProvider), 'u_inv_20');
  });

  group('revealTargetOf', () {
    const graph = SchematicGraph(
      moduleName: 'm',
      cells: <SchematicCell>[],
      boundaryPorts: <SchematicBoundaryPort>[],
      edges: <SchematicEdge>[
        _wire,
        SchematicEdge(
          id: 'e_1_0',
          sourcePortId: 'port:din',
          targetPortId: 'u_load:B',
          netId: 1,
        ),
      ],
    );

    test('names the node that stands for each kind of root', () {
      expect(
        ConeViewController.revealTargetOf(
          const SelectedElement.cell(cellId: 'u_a'),
          null,
        ),
        'u_a',
      );
      expect(
        ConeViewController.revealTargetOf(
          const SelectedElement.port(
            cellId: 'u_a',
            portId: 'u_a:Y',
            portName: 'Y',
          ),
          null,
        ),
        'u_a',
      );
      expect(
        ConeViewController.revealTargetOf(
          const SelectedElement.boundaryPort(
            portId: 'port:din',
            portName: 'din',
          ),
          null,
        ),
        'port:din',
      );
      expect(
        ConeViewController.revealTargetOf(
          const SelectedElement.wire(edgeId: 'e_7_0', netId: 7),
          graph,
        ),
        'u_drv',
      );
      expect(
        ConeViewController.revealTargetOf(
          const SelectedElement.wire(edgeId: 'e_1_0', netId: 1),
          graph,
        ),
        'port:din',
      );
      expect(
        ConeViewController.revealTargetOf(
          const SelectedElement.wire(edgeId: 'e_9_0', netId: 9),
          graph,
        ),
        isNull,
      );
      expect(
        ConeViewController.revealTargetOf(const SelectedElement.none(), graph),
        isNull,
      );
    });
  });
}
