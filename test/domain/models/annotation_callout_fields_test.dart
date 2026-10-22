// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_annotations/crux_annotations_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/structural_witness.dart';

Annotation _note({
  CruxCalloutPlacement placement = const CruxCalloutPlacement(),
  StructuralWitness? witness,
  AnnotationTargetKind kind = AnnotationTargetKind.cell,
}) => Annotation(
  id: 'n1',
  targetKind: kind,
  targetId: 'u_fifo',
  body: 'full flag rises one cycle late',
  createdAtMillis: 10,
  updatedAtMillis: 20,
  moduleName: 'top',
  placement: placement,
  witness: witness,
);

void main() {
  group('callout placement and witness on the annotation record', () {
    test(
      'defaults write nothing, so a 1.1 record is byte-for-byte as before',
      () {
        final json = _note().toJson();
        expect(json.containsKey('labelDx'), isFalse);
        expect(json.containsKey('labelDy'), isFalse);
        expect(json.containsKey('collapsed'), isFalse);
        expect(json.containsKey('witness'), isFalse);
      },
    );

    test('a 1.1 record reads as the default placement and no witness', () {
      final note = Annotation.fromJson(<String, Object?>{
        'id': 'n1',
        'targetKind': 'cell',
        'targetId': 'u_fifo',
        'body': 'b',
        'createdAtMillis': 1,
        'updatedAtMillis': 1,
      })!;
      expect(note.placement, const CruxCalloutPlacement());
      expect(note.witness, isNull);
    });

    test('placement and witness round-trip in the shared record shape', () {
      final note = _note(
        placement: const CruxCalloutPlacement(
          labelDx: 24,
          labelDy: -60,
          collapsed: true,
        ),
        witness: StructuralWitness(const <String, String>{
          'type': r'$dff',
          'param.WIDTH': '1000',
        }),
      );
      final json =
          jsonDecode(jsonEncode(note.toJson())) as Map<String, Object?>;
      expect(json['labelDx'], 24);
      expect(json['labelDy'], -60);
      expect(json['collapsed'], isTrue);
      expect(json['witness'], <String, Object?>{
        'facts': <String, Object?>{'param.WIDTH': '1000', 'type': r'$dff'},
      });
      final back = Annotation.fromJson(json)!;
      expect(back, note);
      expect(back.hashCode, note.hashCode);
    });

    test('a malformed witness is dropped, never fails the note', () {
      final note = Annotation.fromJson(<String, Object?>{
        'id': 'n1',
        'targetKind': 'cell',
        'targetId': 'u_fifo',
        'body': 'b',
        'createdAtMillis': 1,
        'updatedAtMillis': 1,
        'labelDx': 'left',
        'witness': <String, Object?>{
          'facts': <String, Object?>{'type': 3},
        },
      })!;
      expect(note.witness, isNull);
      expect(note.placement, const CruxCalloutPlacement());
    });

    test('copyWith moves the label without touching the element', () {
      final note = _note(witness: StructuralWitness(const {'type': 'x'}));
      final moved = note.copyWith(
        placement: note.placement.nudged(10, 5),
      );
      expect(moved.targetId, note.targetId);
      expect(moved.witness, note.witness);
      expect(moved.placement.labelDx, 10);
      expect(note.copyWith(clearWitness: true).witness, isNull);
    });
  });

  group('the anchor', () {
    test('names its element, and a scope names none', () {
      expect(_note().anchor.elementId, 'u_fifo');
      expect(
        _note(kind: AnnotationTargetKind.scope).anchor.elementId,
        isNull,
      );
      expect(_note().anchor.toJson(), <String, Object?>{
        'targetKind': 'cell',
        'targetId': 'u_fifo',
      });
      expect(
        _note().anchor,
        const AnnotationTarget(
          kind: AnnotationTargetKind.cell,
          targetId: 'u_fifo',
        ),
      );
    });
  });

  group('StructuralWitness', () {
    test('agrees regardless of order, and disagrees on any fact', () {
      final a = StructuralWitness(const {'type': r'$and', 'param.W': '1'});
      expect(
        a.agreesWith(
          StructuralWitness(const {'param.W': '1', 'type': r'$and'}),
        ),
        isTrue,
      );
      expect(
        a.agreesWith(StructuralWitness(const {'type': r'$or', 'param.W': '1'})),
        isFalse,
      );
      expect(a.agreesWith(StructuralWitness(const {'type': r'$and'})), isFalse);
      expect(a.toString(), contains('StructuralWitness'));
    });

    test('rejects unusable payloads', () {
      expect(StructuralWitness.fromJson(null), isNull);
      expect(StructuralWitness.fromJson(<String, Object?>{}), isNull);
      expect(
        StructuralWitness.fromJson(<String, Object?>{
          'facts': <String, Object?>{},
        }),
        isNull,
      );
    });
  });
}
