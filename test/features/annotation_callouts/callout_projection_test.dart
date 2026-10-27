// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/crux_annotations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/annotation_callouts/callout_projection.dart';
import 'package:netcrux/features/viewer/rendering/lod_band.dart';

// A hand-written layout: a cell box at (100, 50) 80 × 40 with a pin box at
// (76, 10) 4 × 4 inside it, a boundary-port box at (10, 60) 20 × 10, and a
// wire routed through four points. Every expected anchor is arithmetic on
// these numbers.
const LaidOutGraph _laidOut = LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_reg',
        bounds: BoundingBox(x: 100, y: 50, width: 80, height: 40),
        ports: <String, BoundingBox>{
          'u_reg:Q': BoundingBox(x: 76, y: 10, width: 4, height: 4),
        },
      ),
      NodePosition(
        id: 'port:clk',
        bounds: BoundingBox(x: 10, y: 60, width: 20, height: 10),
      ),
    ],
    edges: <EdgeRoute>[
      EdgeRoute(
        id: 'e_3_0',
        points: <LayoutPoint>[
          LayoutPoint(180, 62),
          LayoutPoint(200, 62),
          LayoutPoint(200, 100),
          LayoutPoint(240, 100),
        ],
      ),
      EdgeRoute(
        id: 'e_4_0',
        points: <LayoutPoint>[
          LayoutPoint(30, 65),
          LayoutPoint(60, 65),
          LayoutPoint(60, 80),
        ],
      ),
    ],
    bounds: BoundingBox(x: 0, y: 0, width: 300, height: 200),
  ),
);

Annotation _on(AnnotationTargetKind kind, String id) => Annotation(
  id: 'n',
  targetKind: kind,
  targetId: id,
  body: 'b',
  createdAtMillis: 1,
  updatedAtMillis: 1,
);

void main() {
  test('a cell and a boundary port anchor at the middle of their top edge', () {
    expect(
      calloutAnchorInDesign(_laidOut, _on(AnnotationTargetKind.cell, 'u_reg')),
      const Offset(140, 50),
    );
    expect(
      calloutAnchorInDesign(
        _laidOut,
        _on(AnnotationTargetKind.boundaryPort, 'port:clk'),
      ),
      const Offset(20, 60),
    );
  });

  test('a pin anchors at the centre of its box on the cell', () {
    expect(
      calloutAnchorInDesign(
        _laidOut,
        _on(AnnotationTargetKind.port, 'u_reg:Q'),
      ),
      const Offset(178, 62),
    );
  });

  test('a net anchors at the middle of its route', () {
    // Four points: halfway between the second and the third.
    expect(
      calloutAnchorInDesign(_laidOut, _on(AnnotationTargetKind.net, 'e_3_0')),
      const Offset(200, 81),
    );
    // Three points: the middle one.
    expect(
      calloutAnchorInDesign(_laidOut, _on(AnnotationTargetKind.net, 'e_4_0')),
      const Offset(60, 65),
    );
  });

  test('a scope, and an element not on this layout, have no anchor', () {
    for (final (kind, id) in <(AnnotationTargetKind, String)>[
      (AnnotationTargetKind.scope, 'top'),
      (AnnotationTargetKind.cell, 'u_gone'),
      (AnnotationTargetKind.port, 'u_reg:D'),
      (AnnotationTargetKind.port, 'port:clk'),
      (AnnotationTargetKind.net, 'e_9_0'),
    ]) {
      expect(
        calloutAnchorInDesign(_laidOut, _on(kind, id)),
        isNull,
        reason: '$kind $id',
      );
    }
  });

  test('level of detail: balloon, dot, hidden', () {
    expect(calloutDetailFor(LodBand.detail), CruxCalloutDetail.full);
    expect(calloutDetailFor(LodBand.mid), CruxCalloutDetail.dot);
    expect(calloutDetailFor(LodBand.overview), CruxCalloutDetail.hidden);
  });

  test('the excerpt leads with the heading', () {
    expect(calloutExcerpt('FIFO full', ''), 'FIFO full');
    expect(
      calloutExcerpt('FIFO full', 'rises one cycle late'),
      'FIFO full\nrises one cycle late',
    );
  });
}
