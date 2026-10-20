// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Tab order through the Inspector on a cell with an annotation, pinned as
// a transcript that models what NVDA reads on each stop: the header's Go to
// source, the badged Edit Symbol entry, Add Annotation, then the annotation's
// fields and its apply bar. Value rows are not Tab stops. A change in what is
// announced is a change to review.
//
// LOCALE_SWEEP_EXEMPT: the transcript is an English golden of the Tab order;
// every locale's rendering is swept by inspector_panel_test.dart and
// annotation_inspector_section_test.dart.

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/inspector/widgets/inspector_panel.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';

const String _golden =
    'test/features/inspector/widgets/goldens/inspector_cell_annotation.txt';

const _graph = LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'cpu',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_alu',
        kind: CellKind.generic,
        type: 'alu',
        ports: [],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: NetlistLayout(
    nodes: <NodePosition>[],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
  ),
);

void main() {
  testWidgets(
    'the cell Inspector is walked header, symbol, annotations',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer(
        overrides: [
          currentLaidOutGraphProvider.overrideWith((ref) async => _graph),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(annotationStoreProvider)
          .addAnnotation(
            const Annotation(
              id: 'n1',
              targetKind: AnnotationTargetKind.cell,
              targetId: 'u_alu',
              title: 'ALU',
              body: 'Glitches at reset',
              createdAtMillis: 1,
              updatedAtMillis: 1,
            ),
          );
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_alu'));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SizedBox(width: 420, height: 1000, child: InspectorPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final walk = await walkFocus(tester);

      expectCleanFocusWalk(walk, context: 'Inspector, cell u_alu');
      final lines = walk.stops.map((s) => s.line).toList();
      for (final named in const <String>[
        'Go to source',
        'Add Annotation',
        'Title',
        'Body (markdown)',
      ]) {
        expect(
          lines.any((line) => line.contains(named)),
          isTrue,
          reason: '"$named" is not a named Tab stop:\n${walk.transcript}',
        );
      }
      expectFocusWalkGolden(walk, _golden);
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
