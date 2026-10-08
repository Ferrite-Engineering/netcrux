// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/theme/collaborator_palette.dart';
import 'package:netcrux/domain/interfaces/schematic_collaboration_service.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';
import 'package:netcrux/features/annotations/providers/annotation_writing_provider.dart';
import 'package:netcrux/features/collaboration/collab_annotation_adoption.dart';
import 'package:netcrux/features/collaboration/collab_annotation_sync.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';
import 'package:netcrux/services/session/annotation_state.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';

/// Records what the sync sends; the session stream is driven by the test.
class _RecordingService implements SchematicCollaborationService {
  final controller = StreamController<SchematicCollabSessionState?>.broadcast();
  final published = <Annotation>[];
  final withdrawn = <String>[];
  final writing = <bool>[];

  @override
  Stream<SchematicCollabSessionState?> get sessionState => controller.stream;

  @override
  void publishAnnotation(Annotation note) => published.add(note);

  @override
  void withdrawAnnotation(String id) => withdrawn.add(id);

  @override
  void setWritingNote({required bool writing}) => this.writing.add(writing);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _layer = 'session:ABC123';

Annotation _note(
  String id, {
  String body = 'note',
  String? authorId,
  String? layer,
}) => Annotation(
  id: id,
  targetKind: AnnotationTargetKind.cell,
  targetId: 'u_alu',
  body: body,
  createdAtMillis: 1,
  updatedAtMillis: 1,
  authorId: authorId,
  sessionLayerId: layer,
);

SchematicCollabSessionState _session({
  String me = 'grace',
  List<Annotation> shared = const [],
}) => SchematicCollabSessionState(
  sessionId: 'ABC123',
  myParticipantId: me,
  hostId: 'ada',
  mode: SchematicCollabMode.lan,
  participants: const [
    SchematicParticipantInfo(
      id: 'ada',
      displayName: 'Ada',
      colorIndex: 0,
      isHost: true,
    ),
    SchematicParticipantInfo(
      id: 'grace',
      displayName: 'Grace',
      colorIndex: 1,
      isHost: false,
    ),
  ],
  sharedAnnotations: shared,
);

void main() {
  late _RecordingService service;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    List<Annotation> existing = const [],
  }) async {
    service = _RecordingService();
    container = ProviderContainer(
      overrides: [
        schematicCollaborationServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(() => unawaited(service.controller.close()));
    addTearDown(container.dispose);
    container.read(annotationStateProvider.notifier).setAnnotations(existing);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: CollabAnnotationSync(child: SizedBox.shrink()),
        ),
      ),
    );
  }

  Future<void> emit(WidgetTester tester, SchematicCollabSessionState? s) async {
    service.controller.add(s);
    await tester.pump();
  }

  List<Annotation> notes() =>
      container.read(annotationStateProvider).annotations;

  Annotation noteNamed(String id) => notes().singleWhere((n) => n.id == id);

  group('out', () {
    testWidgets('a note written in the session is stamped and travels; one '
        'from before it never does', (tester) async {
      await pump(tester, existing: [_note('private')]);
      await emit(tester, _session());

      container
          .read(annotationStoreProvider)
          .addAnnotation(_note('new', body: 'look here'));
      await tester.pump();

      final stamped = noteNamed('new');
      expect(stamped.sessionLayerId, _layer);
      expect(stamped.authorId, 'grace');
      expect(stamped.author, 'Grace');
      expect(stamped.colorArgb, collaboratorColor(1).toARGB32());
      expect(stamped.sessionLayerLabel, contains('ABC123'));
      expect(service.published.map((n) => n.id), ['new']);

      // Editing the private note changes nothing on the wire.
      container
          .read(annotationStoreProvider)
          .updateAnnotation(_note('private', body: 'still mine'));
      await tester.pump();
      expect(service.published.map((n) => n.id), ['new']);
    });

    testWidgets('an edit republishes; a delete withdraws', (tester) async {
      await pump(tester);
      await emit(tester, _session());
      final store = container.read(annotationStoreProvider)
        ..addAnnotation(_note('new'));
      await tester.pump();

      store.updateAnnotation(noteNamed('new').copyWith(body: 'edited'));
      await tester.pump();
      expect(service.published.last.body, 'edited');

      store.removeAnnotation('new');
      await tester.pump();
      expect(service.withdrawn, ['new']);
    });

    testWidgets('the dialog being open is said, never its text', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, _session());
      container.read(annotationWritingProvider.notifier).start();
      await tester.pump();
      container.read(annotationWritingProvider.notifier).stop();
      await tester.pump();
      expect(service.writing, [true, false]);
    });
  });

  group('in', () {
    final adas = _note(
      'ada-1',
      body: 'clock gate',
      authorId: 'ada',
      layer: _layer,
    );

    testWidgets("somebody else's note arrives, changes and goes", (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, _session(shared: [adas]));
      expect(noteNamed('ada-1'), adas);

      final edited = adas.copyWith(body: 'clock gate, enabled late');
      await emit(tester, _session(shared: [edited]));
      expect(noteNamed('ada-1').body, 'clock gate, enabled late');

      await emit(tester, _session());
      expect(notes(), isEmpty);
    });

    testWidgets('their note is not edited here while their name is on it', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, _session(shared: [adas]));
      container
          .read(annotationStoreProvider)
          .updateAnnotation(adas.copyWith(body: 'tampered'));
      await tester.pump();
      expect(noteNamed('ada-1').body, 'clock gate');
      expect(service.published, isEmpty);
    });

    testWidgets('a guest deleting it removes it here only; it returns if its '
        'author changes it', (tester) async {
      await pump(tester);
      await emit(tester, _session(shared: [adas]));
      container.read(annotationStoreProvider).removeAnnotation('ada-1');
      await tester.pump();
      expect(service.withdrawn, isEmpty);

      await emit(tester, _session(shared: [adas]));
      expect(notes(), isEmpty);

      await emit(tester, _session(shared: [adas.copyWith(body: 'new')]));
      expect(noteNamed('ada-1').body, 'new');
    });

    testWidgets('the host deleting it withdraws it for everyone', (
      tester,
    ) async {
      final graces = _note('g-1', authorId: 'grace', layer: _layer);
      await pump(tester);
      await emit(tester, _session(me: 'ada', shared: [graces]));
      container.read(annotationStoreProvider).removeAnnotation('g-1');
      await tester.pump();
      expect(service.withdrawn, ['g-1']);
    });

    testWidgets('my note, once the room has it, goes when the host removes '
        'it — but not because a state predates it', (tester) async {
      await pump(tester);
      await emit(tester, _session());
      container
          .read(annotationStoreProvider)
          .addAnnotation(
            _note('mine'),
          );
      await tester.pump();
      // A state emitted before the room had the note: it stays.
      await emit(tester, _session());
      expect(notes().map((n) => n.id), ['mine']);

      await emit(tester, _session(shared: [noteNamed('mine')]));
      await emit(tester, _session());
      expect(notes(), isEmpty, reason: 'withdrawn by the host');
    });
  });

  group('at the end', () {
    testWidgets("the session's notes are offered for adoption", (
      tester,
    ) async {
      final adas = _note('ada-1', authorId: 'ada', layer: _layer);
      await pump(tester, existing: [_note('private')]);
      await emit(tester, _session(shared: [adas]));
      container
          .read(annotationStoreProvider)
          .addAnnotation(
            _note('mine'),
          );
      await tester.pump();

      await emit(tester, null);
      final offer = container.read(collabAdoptionOfferProvider);
      expect(offer!.noteCount, 2);
      expect(offer.authorCount, 2);

      container
          .read(collabAdoptionOfferProvider.notifier)
          .decide(CollabAdoptionChoice.keepMine);
      expect(notes().map((n) => n.id), ['private', 'mine']);
      expect(noteNamed('mine').authorId, isNull);
    });

    testWidgets('a session that wrote nothing here offers nothing', (
      tester,
    ) async {
      await pump(tester, existing: [_note('private')]);
      await emit(tester, _session());
      await emit(tester, null);
      expect(container.read(collabAdoptionOfferProvider), isNull);
    });
  });
}
