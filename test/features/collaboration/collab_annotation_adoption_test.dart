// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/features/collaboration/collab_annotation_adoption.dart';

Annotation _note(String id, {String? layer, String? authorId}) => Annotation(
  id: id,
  targetKind: BookmarkTargetKind.cell,
  targetId: 'u',
  body: id,
  createdAtMillis: 1,
  updatedAtMillis: 1,
  authorId: authorId,
  colorArgb: layer == null ? null : 0xFF112233,
  sessionLayerId: layer,
);

void main() {
  const layer = 'session:ABC123';
  final notes = [
    _note('private'),
    _note('mine', layer: layer, authorId: 'me'),
    _note('theirs', layer: layer, authorId: 'grace'),
    _note('lastWeek', layer: 'session:OLD', authorId: 'alan'),
  ];

  List<String> ids(List<Annotation> list) => [for (final n in list) n.id];

  test('keep all keeps the meeting, and my notes become mine to edit', () {
    final kept = adoptSessionLayer(
      notes,
      layerId: layer,
      myId: 'me',
      choice: CollabAdoptionChoice.keepAll,
    );
    expect(ids(kept), ['private', 'mine', 'theirs', 'lastWeek']);
    expect(kept[1].authorId, isNull);
    expect(kept[1].colorArgb, 0xFF112233, reason: 'the colour stays frozen');
    expect(kept[2].authorId, 'grace', reason: 'attribution stays read-only');
  });

  test('keep only mine drops the others of this session only', () {
    final kept = adoptSessionLayer(
      notes,
      layerId: layer,
      myId: 'me',
      choice: CollabAdoptionChoice.keepMine,
    );
    expect(ids(kept), ['private', 'mine', 'lastWeek']);
  });

  test("discard removes this session's notes and nothing else", () {
    final kept = adoptSessionLayer(
      notes,
      layerId: layer,
      myId: 'me',
      choice: CollabAdoptionChoice.discard,
    );
    expect(ids(kept), ['private', 'lastWeek']);
  });

  group('the offer', () {
    test('is answered once, then gone', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final chosen = <CollabAdoptionChoice>[];
      final notifier = container.read(collabAdoptionOfferProvider.notifier)
        ..offer(
          CollabAdoptionOffer(
            layerId: layer,
            noteCount: 2,
            authorCount: 2,
            apply: chosen.add,
          ),
        );
      expect(container.read(collabAdoptionOfferProvider), isNotNull);

      notifier
        ..decide(CollabAdoptionChoice.discard)
        ..decide(CollabAdoptionChoice.keepAll);
      expect(chosen, [CollabAdoptionChoice.discard]);
      expect(container.read(collabAdoptionOfferProvider), isNull);
    });

    test('an unanswered offer replaced by another keeps all', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final first = <CollabAdoptionChoice>[];
      container.read(collabAdoptionOfferProvider.notifier)
        ..offer(
          CollabAdoptionOffer(
            layerId: layer,
            noteCount: 1,
            authorCount: 1,
            apply: first.add,
          ),
        )
        ..offer(
          CollabAdoptionOffer(
            layerId: 'session:NEXT',
            noteCount: 1,
            authorCount: 1,
            apply: (_) {},
          ),
        );
      expect(first, [CollabAdoptionChoice.keepAll]);
    });
  });
}
