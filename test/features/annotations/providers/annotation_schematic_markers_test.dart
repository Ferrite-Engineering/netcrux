import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/features/annotations/providers/annotation_schematic_markers.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/services/schematic/schematic_annotation_markers_provider.dart';
import 'package:netcrux/services/session/annotation_state.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';
import 'package:netcrux/services/session/in_session_annotation_store.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

Annotation _a(
  String id,
  AnnotationTargetKind kind,
  String targetId, {
  String? moduleName,
}) => Annotation(
  id: id,
  targetKind: kind,
  targetId: targetId,
  body: 'b',
  createdAtMillis: 1,
  updatedAtMillis: 1,
  moduleName: moduleName,
);

void main() {
  late ProviderContainer container;
  setUp(() {
    container = ProviderContainer(
      overrides: [
        annotationStoreProvider.overrideWith(
          InSessionAnnotationStore.new,
        ),
        schematicAnnotationMarkersProvider.overrideWith(
          annotationSchematicMarkers,
        ),
      ],
    );
    container
        .read(hierarchyTreeProvider.notifier)
        .setModel(
          const YosysJsonParser().parse(
            File(
              'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
            ).readAsStringSync(),
          ),
        );
  });
  tearDown(() => container.dispose());

  test('no annotations publish no markers', () {
    expect(container.read(schematicAnnotationMarkersProvider), isNull);
  });

  test('cell, pin and boundary-port notes on this scope become markers', () {
    container.read(annotationStoreProvider)
      ..addAnnotation(
        _a('a1', AnnotationTargetKind.cell, 'u_cpu', moduleName: 'top'),
      )
      ..addAnnotation(
        _a('a2', AnnotationTargetKind.port, 'u_cpu:CLK', moduleName: 'top'),
      )
      ..addAnnotation(
        _a(
          'a3',
          AnnotationTargetKind.boundaryPort,
          'port:clk',
          moduleName: 'top',
        ),
      );
    final markers = container.read(schematicAnnotationMarkersProvider)!;
    expect(markers.cells.keys, <String>['u_cpu']);
    expect(markers.pins.keys, <String>['u_cpu:CLK']);
    expect(markers.boundaryPorts.keys, <String>['port:clk']);
  });

  test('net and scope notes publish no markers', () {
    container.read(annotationStoreProvider)
      ..addAnnotation(_a('a1', AnnotationTargetKind.net, 'e_2_0'))
      ..addAnnotation(_a('a2', AnnotationTargetKind.scope, 'u_cpu'));
    expect(container.read(schematicAnnotationMarkersProvider), isNull);
  });

  test("another module's note publishes nothing here", () {
    container
        .read(annotationStoreProvider)
        .addAnnotation(
          _a('a1', AnnotationTargetKind.cell, 'u_alu', moduleName: 'cpu'),
        );
    expect(container.read(schematicAnnotationMarkersProvider), isNull);
  });

  test('the markers follow the state as notes are added and removed', () {
    final store = container.read(annotationStoreProvider)
      ..addAnnotation(_a('a1', AnnotationTargetKind.cell, 'u_cpu'))
      ..addAnnotation(_a('a2', AnnotationTargetKind.cell, 'u_cpu'));
    expect(
      container
          .read(schematicAnnotationMarkersProvider)!
          .cells['u_cpu']!
          .annotationIds,
      <String>['a1', 'a2'],
    );
    store
      ..removeAnnotation('a1')
      ..removeAnnotation('a2');
    expect(
      container.read(annotationStateProvider).annotations,
      isEmpty,
    );
    expect(container.read(schematicAnnotationMarkersProvider), isNull);
  });
}
