// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/services/cone_of_influence_controller.dart';
import 'package:netcrux/services/schematic/cone_of_influence_service_provider.dart';

/// `driver -> sink` over net 1, laid out at distinct positions so the cone
/// has real bounds to frame.
LaidOutGraph _fixture() => const LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'driver',
        kind: CellKind.generic,
        type: 'src',
        ports: <SchematicPort>[],
      ),
      SchematicCell(
        id: 'sink',
        kind: CellKind.generic,
        type: 'dst',
        ports: <SchematicPort>[],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: NetlistLayout(
    bounds: BoundingBox(x: 0, y: 0, width: 300, height: 100),
    nodes: <NodePosition>[
      NodePosition(
        id: 'driver',
        bounds: BoundingBox(x: 0, y: 0, width: 60, height: 40),
      ),
      NodePosition(
        id: 'sink',
        bounds: BoundingBox(x: 200, y: 10, width: 60, height: 40),
      ),
    ],
    edges: <EdgeRoute>[],
  ),
);

/// Returns a fixed overlay so the controller's compute → paint → frame
/// wiring is exercised without the Pro BFS implementation.
class _FakeConeService implements ConeOfInfluenceService {
  const _FakeConeService(this._overlay);
  final TraceOverlay _overlay;

  @override
  TraceOverlay compute(ConeOfInfluenceRequest request) => _overlay;

  @override
  Future<TraceOverlay> computeAsync(ConeOfInfluenceRequest request) async =>
      _overlay;
}

const _coneOverlay = TraceOverlay(
  mode: TraceOverlayMode.fanout,
  highlightedCellIds: <String>{'driver', 'sink'},
  highlightedEdgeIds: <String>{},
  highlightedBoundaryPortIds: <String>{},
);

ProviderContainer _container({
  LaidOutGraph? laidOut,
  ConeOfInfluenceService? service,
}) {
  final container = ProviderContainer(
    overrides: [
      currentLaidOutGraphProvider.overrideWith(
        (ref) => laidOut ?? Completer<LaidOutGraph>().future,
      ),
      if (service != null)
        coneOfInfluenceServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  // The controller's fit-to-cone reads the canvas GlobalKey's currentContext,
  // which touches WidgetsBinding.instance — initialize the test binding so
  // that access returns null (no canvas mounted) instead of throwing.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConeOfInfluenceController.coneBounds', () {
    test('unions the bounds of every cone cell', () {
      final bounds = ConeOfInfluenceController.coneBounds(
        _fixture(),
        <String>{'driver', 'sink'},
      );
      // driver (0,0,60,40) ∪ sink (200,10,60,40) = (0,0,260,50).
      expect(bounds, isNotNull);
      expect(bounds!.x, 0);
      expect(bounds.y, 0);
      expect(bounds.width, 260);
      expect(bounds.height, 50);
    });

    test('ignores ids with no laid-out node; null when none resolve', () {
      final bounds = ConeOfInfluenceController.coneBounds(
        _fixture(),
        <String>{'driver', 'ghost'},
      );
      expect(bounds!.width, 60); // only driver contributes
      expect(
        ConeOfInfluenceController.coneBounds(_fixture(), <String>{'ghost'}),
        isNull,
      );
    });
  });

  group('ConeOfInfluenceController.run', () {
    test('paints the cone and returns its cell count', () async {
      final container = _container(
        laidOut: _fixture(),
        service: const _FakeConeService(_coneOverlay),
      );
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'driver'));

      final count = await ConeOfInfluenceController.fromContainer(
        container,
      ).run(ConeOfInfluenceMode.fanout);

      expect(count, 2);
      final overlay = container.read(traceOverlayProvider);
      expect(
        overlay.highlightedCellIds,
        containsAll(<String>['driver', 'sink']),
      );
    });

    test('returns null and leaves the overlay untouched with no selection', () {
      final container = _container(
        laidOut: _fixture(),
        service: const _FakeConeService(_coneOverlay),
      );
      expect(
        ConeOfInfluenceController.fromContainer(
          container,
        ).run(ConeOfInfluenceMode.fanin),
        completion(isNull),
      );
      expect(container.read(traceOverlayProvider).isEmpty, isTrue);
    });

    test('returns null when nothing is laid out yet', () {
      final container = _container(
        service: const _FakeConeService(_coneOverlay),
      );
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'driver'));
      expect(
        ConeOfInfluenceController.fromContainer(
          container,
        ).run(ConeOfInfluenceMode.fanin),
        completion(isNull),
      );
    });
  });
}
