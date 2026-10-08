// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/annotation.dart';

/// What to keep of a session's notes when it ends.
enum CollabAdoptionChoice {
  /// Every note the session produced. Also what dismissing the offer means:
  /// silently discarding a meeting's notes would destroy what the meeting was
  /// for.
  keepAll,

  /// Only the notes the local participant wrote.
  keepMine,

  /// None of them.
  discard,
}

/// The session's notes after [choice], given [notes] (a tab's notes) and
/// [myId] (the local participant in the session that wrote [layerId]).
///
/// Notes outside the layer are untouched. Kept notes stay in their layer, so
/// they can still be hidden or deleted as a unit, keep their author's frozen
/// colour, and keep their attribution — except the local participant's own,
/// which lose their author id and are theirs to edit again.
List<Annotation> adoptSessionLayer(
  List<Annotation> notes, {
  required String layerId,
  required String myId,
  required CollabAdoptionChoice choice,
}) => [
  for (final note in notes)
    if (note.sessionLayerId != layerId)
      note
    else if (choice != CollabAdoptionChoice.discard &&
        (note.authorId == null || note.authorId == myId))
      note.copyWith(clearAuthorId: true)
    else if (choice == CollabAdoptionChoice.keepAll)
      note,
];

/// One tab's session notes, waiting for the local participant to say what to
/// keep now that the session has ended.
@immutable
final class CollabAdoptionOffer {
  /// Creates an offer.
  const CollabAdoptionOffer({
    required this.layerId,
    required this.noteCount,
    required this.authorCount,
    required this.apply,
  });

  /// The session layer the notes belong to.
  final String layerId;

  /// How many notes the session produced in that tab.
  final int noteCount;

  /// How many people wrote them.
  final int authorCount;

  /// Applies a choice to the tab the notes are in.
  final void Function(CollabAdoptionChoice choice) apply;

  @override
  bool operator ==(Object other) =>
      other is CollabAdoptionOffer &&
      other.layerId == layerId &&
      other.noteCount == noteCount &&
      other.authorCount == authorCount;

  @override
  int get hashCode => Object.hash(layerId, noteCount, authorCount);
}

/// The pending adoption offer, or `null`. Root-scoped: the offer outlives the
/// session and is answered from workspace chrome.
final collabAdoptionOfferProvider =
    NotifierProvider<CollabAdoptionOfferNotifier, CollabAdoptionOffer?>(
      CollabAdoptionOfferNotifier.new,
      name: 'collabAdoptionOfferProvider',
    );

/// Notifier behind [collabAdoptionOfferProvider].
class CollabAdoptionOfferNotifier extends Notifier<CollabAdoptionOffer?> {
  @override
  CollabAdoptionOffer? build() => null;

  /// Puts [offer] up. A previous offer still unanswered is kept — the
  /// loss-averse reading of a question nobody answered.
  void offer(CollabAdoptionOffer offer) {
    state?.apply(CollabAdoptionChoice.keepAll);
    state = offer;
  }

  /// Answers the offer with [choice].
  void decide(CollabAdoptionChoice choice) {
    final pending = state;
    if (pending == null) return;
    state = null;
    pending.apply(choice);
  }
}
