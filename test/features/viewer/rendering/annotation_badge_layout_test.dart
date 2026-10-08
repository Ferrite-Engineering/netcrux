// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/viewer/rendering/annotation_badge_layout.dart';
import 'package:netcrux/features/viewer/rendering/lod_band.dart';
import 'package:netcrux/services/schematic/schematic_annotation_markers_provider.dart';

import '../../../support/color_metrics.dart';

/// A cell `u_and` at (20, 30) 80 x 60 with a pin `u_and:Y` at (76, 28)
/// 4 x 4 on it, and a boundary port `port:y` at (160, 30) 16 x 16.
LaidOutGraph badgeGraph() {
  const graph = SchematicGraph(
    moduleName: 'and2',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_and',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[
          SchematicPort(
            id: 'u_and:Y',
            name: 'Y',
            direction: PortDirection.output,
            side: SchematicPortSide.east,
          ),
        ],
      ),
      SchematicCell(
        id: 'u_or',
        kind: CellKind.orGate,
        type: r'$or',
        ports: <SchematicPort>[],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[
      SchematicBoundaryPort(
        id: 'port:y',
        name: 'y',
        direction: PortDirection.output,
        width: 1,
      ),
    ],
    edges: <SchematicEdge>[],
  );
  const layout = NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_and',
        bounds: BoundingBox(x: 20, y: 30, width: 80, height: 60),
        ports: <String, BoundingBox>{
          'u_and:Y': BoundingBox(x: 76, y: 28, width: 4, height: 4),
        },
      ),
      NodePosition(
        id: 'u_or',
        bounds: BoundingBox(x: 20, y: 130, width: 80, height: 60),
      ),
      NodePosition(
        id: 'port:y',
        bounds: BoundingBox(x: 160, y: 30, width: 16, height: 16),
      ),
    ],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 200, height: 200),
  );
  return const LaidOutGraph(graph: graph, layout: layout);
}

SchematicAnnotationMarker marker(AnnotationTargetKind kind, String id) =>
    SchematicAnnotationMarker(
      kind: kind,
      targetId: id,
      annotationIds: <String>['a-$id'],
    );

void main() {
  group('AnnotationBadgeLayout.place', () {
    test('a cell badge sits on the cell box top-right corner', () {
      final badges = AnnotationBadgeLayout.place(
        badgeGraph(),
        SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
          marker(AnnotationTargetKind.cell, 'u_and'),
        ]),
      );
      expect(badges.single.center, const Offset(100, 30));
    });

    test('a pin badge sits on the pin box corner, not the cell corner', () {
      final badges = AnnotationBadgeLayout.place(
        badgeGraph(),
        SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
          marker(AnnotationTargetKind.port, 'u_and:Y'),
        ]),
      );
      // The pin box is (20 + 76, 30 + 28) 4 x 4.
      expect(badges.single.center, const Offset(100, 58));
    });

    test('a boundary-port badge sits on the port box corner', () {
      final badges = AnnotationBadgeLayout.place(
        badgeGraph(),
        SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
          marker(AnnotationTargetKind.boundaryPort, 'port:y'),
        ]),
      );
      expect(badges.single.center, const Offset(176, 30));
    });

    test('a marker for an element not on this layout places nothing', () {
      final badges = AnnotationBadgeLayout.place(
        badgeGraph(),
        SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
          marker(AnnotationTargetKind.cell, 'u_elsewhere'),
          marker(AnnotationTargetKind.port, 'u_elsewhere:A'),
          marker(AnnotationTargetKind.port, 'u_and:NOPE'),
          marker(AnnotationTargetKind.boundaryPort, 'port:nope'),
        ]),
      );
      expect(badges, isEmpty);
    });
  });

  group('AnnotationBadgeLayout bands and radius', () {
    test('badges are drawn in the mid and detail bands only', () {
      expect(AnnotationBadgeLayout.drawnIn(LodBand.detail), isTrue);
      expect(AnnotationBadgeLayout.drawnIn(LodBand.mid), isTrue);
      expect(AnnotationBadgeLayout.drawnIn(LodBand.overview), isFalse);
    });

    test('the radius holds a minimum on screen as the zoom drops', () {
      expect(
        AnnotationBadgeLayout.radiusAt(1),
        AnnotationBadgeLayout.designRadius,
      );
      expect(
        AnnotationBadgeLayout.radiusAt(0.3) * 0.3,
        closeTo(AnnotationBadgeLayout.minScreenRadius, 1e-9),
      );
    });
  });

  group('AnnotationBadgeLayout.hitTest', () {
    final markers = SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
      marker(AnnotationTargetKind.cell, 'u_and'),
    ]);

    test('a point on the badge hits its marker', () {
      final hit = AnnotationBadgeLayout.hitTest(
        laidOut: badgeGraph(),
        markers: markers,
        zoom: 1,
        designPoint: const Offset(103, 27),
      );
      expect(hit?.marker.targetId, 'u_and');
    });

    test('a point inside the cell but off the badge misses', () {
      final hit = AnnotationBadgeLayout.hitTest(
        laidOut: badgeGraph(),
        markers: markers,
        zoom: 1,
        designPoint: const Offset(60, 60),
      );
      expect(hit, isNull);
    });

    test('the overview band has no badge to hit', () {
      final hit = AnnotationBadgeLayout.hitTest(
        laidOut: badgeGraph(),
        markers: markers,
        zoom: 0.1,
        designPoint: const Offset(100, 30),
      );
      expect(hit, isNull);
    });
  });

  group('AnnotationBadgeColors', () {
    // WCAG 2.1 SC 1.4.11: a graphical object needs 3:1 against what is
    // next to it. The disc must read against the canvas, the glyph against
    // the disc.
    for (final preset in builtinPresets().values) {
      test('reads on the ${preset.id} preset', () {
        final theme = themeOfPreset(preset);
        final colors = AnnotationBadgeColors.of(theme);
        expect(
          contrastRatio(colors.fill, theme.colorScheme.surface),
          greaterThanOrEqualTo(3),
          reason: 'badge disc against the canvas background',
        );
        expect(
          contrastRatio(colors.glyph, colors.fill),
          greaterThanOrEqualTo(3),
          reason: 'note glyph against the disc',
        );
      });
    }

    test('there are six built-in presets to read on', () {
      expect(builtinPresets(), hasLength(6));
    });
  });
}
