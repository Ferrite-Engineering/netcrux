// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_annotations/crux_annotations_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/structural_witness.dart';
import 'package:netcrux/features/annotations/providers/annotation_statuses_provider.dart';
import 'package:netcrux/features/annotations/services/annotation_drift.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';
import 'package:netcrux/services/session/in_session_annotation_store.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

// Hand-written Yosys `write_json` documents. Every expectation below is read
// off these documents by eye (the cell types and parameters, the pin
// directions, which bit each output drives), never from the code under test.
//
// v1: `top` holds an 8-bit register u_reg ($dff, Q drives bit 3) and an AND
// gate u_and ($and, A from bit 3, Y drives bit 6); input clk is bit 4; module
// `sub` holds an inverter u_inv.
// v2 is v1 elaborated again after an edit: u_reg is 16 bits wide, u_and is
// now an $or (same instance name), and u_inv is gone.
String _design({required bool v2}) => jsonEncode(<String, Object?>{
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': <String, Object?>{'top': '1'},
      'ports': <String, Object?>{
        'clk': <String, Object?>{
          'direction': 'input',
          'bits': <int>[4],
        },
        'd': <String, Object?>{
          'direction': 'input',
          'bits': <int>[2],
        },
        'y': <String, Object?>{
          'direction': 'output',
          'bits': <int>[6],
        },
      },
      'cells': <String, Object?>{
        'u_reg': <String, Object?>{
          'hide_name': 0,
          'type': r'$dff',
          'parameters': <String, Object?>{'WIDTH': v2 ? '10000' : '1000'},
          'attributes': <String, Object?>{},
          'port_directions': <String, Object?>{
            'CLK': 'input',
            'D': 'input',
            'Q': 'output',
          },
          'connections': <String, Object?>{
            'CLK': <int>[4],
            'D': <int>[2],
            'Q': <int>[3],
          },
        },
        'u_and': <String, Object?>{
          'hide_name': 0,
          'type': v2 ? r'$or' : r'$and',
          'parameters': <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': <String, Object?>{
            'A': 'input',
            'B': 'input',
            'Y': 'output',
          },
          'connections': <String, Object?>{
            'A': <int>[3],
            'B': <int>[2],
            'Y': <int>[6],
          },
        },
      },
      'netnames': <String, Object?>{
        'd': <String, Object?>{
          'hide_name': 0,
          'bits': <int>[2],
          'attributes': <String, Object?>{},
        },
        'q': <String, Object?>{
          'hide_name': 0,
          'bits': <int>[3],
          'attributes': <String, Object?>{},
        },
        'clk': <String, Object?>{
          'hide_name': 0,
          'bits': <int>[4],
          'attributes': <String, Object?>{},
        },
        'y': <String, Object?>{
          'hide_name': 0,
          'bits': <int>[6],
          'attributes': <String, Object?>{},
        },
      },
    },
    'sub': <String, Object?>{
      'attributes': <String, Object?>{},
      'ports': <String, Object?>{},
      'cells': <String, Object?>{
        if (!v2)
          'u_inv': <String, Object?>{
            'hide_name': 0,
            'type': r'$not',
            'parameters': <String, Object?>{},
            'attributes': <String, Object?>{},
            'port_directions': <String, Object?>{'A': 'input', 'Y': 'output'},
            'connections': <String, Object?>{
              'A': <int>[7],
              'Y': <int>[8],
            },
          },
      },
      'netnames': <String, Object?>{},
    },
  },
});

NetlistModel _model({bool v2 = false}) =>
    const YosysJsonParser().parse(_design(v2: v2));

Annotation _note(
  String id,
  AnnotationTargetKind kind,
  String targetId, {
  String? module,
  StructuralWitness? witness,
}) => Annotation(
  id: id,
  targetKind: kind,
  targetId: targetId,
  body: 'note',
  createdAtMillis: 1,
  updatedAtMillis: 1,
  moduleName: module,
  witness: witness,
);

void main() {
  final top = _model().modules['top']!;

  group('readStructuralWitness', () {
    test('a cell records its type and parameters', () {
      expect(
        readStructuralWitness(
          top,
          kind: AnnotationTargetKind.cell,
          targetId: 'u_reg',
        )!.facts,
        <String, String>{'type': r'$dff', 'param.WIDTH': '1000'},
      );
    });

    test("a pin records its cell's type and its own direction and width", () {
      expect(
        readStructuralWitness(
          top,
          kind: AnnotationTargetKind.port,
          targetId: 'u_reg:Q',
        )!.facts,
        <String, String>{
          'type': r'$dff',
          'param.WIDTH': '1000',
          'pin.direction': 'output',
          'pin.width': '1',
        },
      );
    });

    test('a boundary port records its direction and width', () {
      expect(
        readStructuralWitness(
          top,
          kind: AnnotationTargetKind.boundaryPort,
          targetId: 'port:clk',
        )!.facts,
        <String, String>{'direction': 'input', 'width': '1'},
      );
    });

    test('a net records its driver: a cell output, or an input port', () {
      expect(
        readStructuralWitness(
          top,
          kind: AnnotationTargetKind.net,
          targetId: 'e_3_0',
        )!.facts,
        <String, String>{'driver': r'cell:u_reg.Q:$dff'},
      );
      expect(
        readStructuralWitness(
          top,
          kind: AnnotationTargetKind.net,
          targetId: 'e_4_1',
        )!.facts,
        <String, String>{'driver': 'port:clk'},
      );
    });

    test('a scope, and an element the module lacks, record nothing', () {
      expect(
        readStructuralWitness(
          top,
          kind: AnnotationTargetKind.scope,
          targetId: 'top',
        ),
        isNull,
      );
      for (final (kind, id) in <(AnnotationTargetKind, String)>[
        (AnnotationTargetKind.cell, 'u_gone'),
        (AnnotationTargetKind.port, 'u_reg:NOPE'),
        (AnnotationTargetKind.boundaryPort, 'port:nope'),
        (AnnotationTargetKind.net, 'e_99_0'),
        (AnnotationTargetKind.net, 'not-an-edge'),
      ]) {
        expect(
          readStructuralWitness(top, kind: kind, targetId: id),
          isNull,
          reason: '$kind $id',
        );
        expect(
          annotationElementExists(top, kind: kind, targetId: id),
          isFalse,
          reason: '$kind $id',
        );
      }
    });
  });

  test('capture reads the named module and nothing without one', () {
    final model = _model();
    expect(
      captureAnnotationWitness(
        model,
        kind: AnnotationTargetKind.cell,
        targetId: 'u_inv',
        moduleName: 'sub',
      )!.facts['type'],
      r'$not',
    );
    expect(
      captureAnnotationWitness(
        model,
        kind: AnnotationTargetKind.cell,
        targetId: 'u_reg',
        moduleName: null,
      ),
      isNull,
    );
    expect(
      captureAnnotationWitness(
        null,
        kind: AnnotationTargetKind.cell,
        targetId: 'u_reg',
        moduleName: 'top',
      ),
      isNull,
    );
  });

  group('annotationStatuses', () {
    StructuralWitness witnessOf(
      AnnotationTargetKind kind,
      String id, {
      String module = 'top',
    }) => captureAnnotationWitness(
      _model(),
      kind: kind,
      targetId: id,
      moduleName: module,
    )!;

    final notes = <Annotation>[
      _note(
        'reg',
        AnnotationTargetKind.cell,
        'u_reg',
        module: 'top',
        witness: witnessOf(AnnotationTargetKind.cell, 'u_reg'),
      ),
      _note(
        'and',
        AnnotationTargetKind.cell,
        'u_and',
        module: 'top',
        witness: witnessOf(AnnotationTargetKind.cell, 'u_and'),
      ),
      _note(
        'q',
        AnnotationTargetKind.net,
        'e_3_0',
        module: 'top',
        witness: witnessOf(AnnotationTargetKind.net, 'e_3_0'),
      ),
      _note(
        'inv',
        AnnotationTargetKind.cell,
        'u_inv',
        module: 'sub',
        witness: witnessOf(AnnotationTargetKind.cell, 'u_inv', module: 'sub'),
      ),
      _note('scope', AnnotationTargetKind.scope, 'top.u_sub'),
      _note('plain', AnnotationTargetKind.boundaryPort, 'port:clk'),
    ];

    test('as written: resolved here, outside the scope there', () {
      expect(
        annotationStatuses(notes, model: _model(), currentModule: 'top'),
        <String, CruxAnnotationStatus>{
          'reg': CruxAnnotationStatus.resolved,
          'and': CruxAnnotationStatus.resolved,
          'q': CruxAnnotationStatus.resolved,
          'inv': CruxAnnotationStatus.orphaned,
          'scope': CruxAnnotationStatus.unanchoredToRow,
          'plain': CruxAnnotationStatus.resolved,
        },
      );
    });

    test('opening the child scope draws its notes and lists the parent', () {
      final statuses = annotationStatuses(
        notes,
        model: _model(),
        currentModule: 'sub',
      );
      expect(statuses['inv'], CruxAnnotationStatus.resolved);
      expect(statuses['reg'], CruxAnnotationStatus.orphaned);
    });

    test(
      'after re-elaboration: changed elements drift, removed are missing',
      () {
        expect(
          annotationStatuses(
            notes,
            model: _model(v2: true),
            currentModule: 'top',
          ),
          <String, CruxAnnotationStatus>{
            // WIDTH went from 8 to 16.
            'reg': CruxAnnotationStatus.drifted,
            // Same instance name, an $or where an $and was.
            'and': CruxAnnotationStatus.drifted,
            // u_reg still drives q: the net's witness holds.
            'q': CruxAnnotationStatus.resolved,
            // u_inv was removed.
            'inv': CruxAnnotationStatus.unresolved,
            'scope': CruxAnnotationStatus.unanchoredToRow,
            // No witness recorded: nothing to compare, never drift.
            'plain': CruxAnnotationStatus.resolved,
          },
        );
      },
    );

    test('a note saved before the module was recorded is found by search', () {
      final legacy = <Annotation>[
        _note('here', AnnotationTargetKind.cell, 'u_reg'),
        _note('there', AnnotationTargetKind.cell, 'u_inv'),
        _note('nowhere', AnnotationTargetKind.cell, 'u_ghost'),
      ];
      expect(
        annotationStatuses(legacy, model: _model(), currentModule: 'top'),
        <String, CruxAnnotationStatus>{
          'here': CruxAnnotationStatus.resolved,
          'there': CruxAnnotationStatus.orphaned,
          'nowhere': CruxAnnotationStatus.unresolved,
        },
      );
    });

    test('with no design loaded nothing is classified', () {
      expect(
        annotationStatuses(notes, model: null, currentModule: null),
        isEmpty,
      );
    });
  });

  test('the per-tab provider follows the annotations and the scope', () {
    final container = ProviderContainer(
      overrides: [
        annotationStoreProvider.overrideWith(InSessionAnnotationStore.new),
        annotationStatusesProvider.overrideWith(annotationStatusesForTab),
      ],
    );
    addTearDown(container.dispose);
    container.read(hierarchyTreeProvider.notifier).setModel(_model());
    container
        .read(annotationStoreProvider)
        .addAnnotation(
          _note(
            'reg',
            AnnotationTargetKind.cell,
            'u_reg',
            module: 'top',
            witness: captureAnnotationWitness(
              _model(),
              kind: AnnotationTargetKind.cell,
              targetId: 'u_reg',
              moduleName: 'top',
            ),
          ),
        );
    expect(
      container.read(annotationStatusesProvider),
      <String, CruxAnnotationStatus>{'reg': CruxAnnotationStatus.resolved},
    );
    container.read(hierarchyTreeProvider.notifier).setModel(_model(v2: true));
    expect(
      container.read(annotationStatusesProvider)['reg'],
      CruxAnnotationStatus.drifted,
    );
  });

  test('the root instance is empty: the root has no design', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(annotationStatusesProvider), isEmpty);
  });
}
