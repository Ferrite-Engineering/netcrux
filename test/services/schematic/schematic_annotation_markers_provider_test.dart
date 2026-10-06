// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/services/schematic/schematic_annotation_markers_provider.dart';

SchematicAnnotationMarker _m(
  BookmarkTargetKind kind,
  String id, [
  List<String> ids = const <String>['a1'],
]) => SchematicAnnotationMarker(kind: kind, targetId: id, annotationIds: ids);

void main() {
  test('open core publishes no markers', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(schematicAnnotationMarkersProvider), isNull);
  });

  test('from() sorts markers by the kind the canvas badges', () {
    final markers = SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
      _m(BookmarkTargetKind.cell, 'u_alu'),
      _m(BookmarkTargetKind.port, 'u_alu:A'),
      _m(BookmarkTargetKind.boundaryPort, 'port:clk'),
    ]);
    expect(markers.cells.keys, <String>['u_alu']);
    expect(markers.pins.keys, <String>['u_alu:A']);
    expect(markers.boundaryPorts.keys, <String>['port:clk']);
    expect(markers.all, hasLength(3));
    expect(markers.isEmpty, isFalse);
  });

  test('from() drops nets, scopes and markers with no annotation', () {
    final markers = SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
      _m(BookmarkTargetKind.net, 'e_4_0'),
      _m(BookmarkTargetKind.scope, 'top.cpu'),
      _m(BookmarkTargetKind.cell, 'u_alu', const <String>[]),
    ]);
    expect(markers.isEmpty, isTrue);
    expect(markers, SchematicAnnotationMarkers.empty);
  });

  test('two notes on one element merge into one marker, in order', () {
    final markers = SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
      _m(BookmarkTargetKind.cell, 'u_alu', const <String>['a0']),
      _m(BookmarkTargetKind.cell, 'u_alu', const <String>['a2']),
    ]);
    expect(markers.cells['u_alu']!.annotationIds, <String>['a0', 'a2']);
  });

  test('equality is by content', () {
    SchematicAnnotationMarkers build() =>
        SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
          _m(BookmarkTargetKind.cell, 'u_alu'),
          _m(BookmarkTargetKind.port, 'u_alu:A'),
        ]);
    expect(build(), build());
    expect(build().hashCode, build().hashCode);
    expect(
      build(),
      isNot(
        SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
          _m(BookmarkTargetKind.cell, 'u_alu', const <String>['a9']),
        ]),
      ),
    );
  });
}
