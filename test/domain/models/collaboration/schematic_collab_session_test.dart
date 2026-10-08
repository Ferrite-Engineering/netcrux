// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';

void main() {
  const ada = SchematicParticipantInfo(
    id: 'ada',
    displayName: 'Ada',
    colorIndex: 0,
    isHost: true,
  );
  const grace = SchematicParticipantInfo(
    id: 'grace',
    displayName: 'Grace',
    colorIndex: 1,
    isHost: false,
  );

  SchematicCollabSessionState state({
    String me = 'ada',
    String? presenterId,
  }) => SchematicCollabSessionState(
    sessionId: 'ABC123',
    myParticipantId: me,
    hostId: 'ada',
    mode: SchematicCollabMode.lan,
    participants: const [ada, grace],
    presenterId: presenterId,
  );

  group('presenter', () {
    test('defaults to the host until the token moves', () {
      expect(state().effectivePresenterId, 'ada');
      expect(state().isLocalPresenter, isTrue);
      expect(state(me: 'grace').isLocalPresenter, isFalse);
      expect(state().presenter, ada);
    });

    test('follows the token once it moves', () {
      final moved = state(presenterId: 'grace');
      expect(moved.effectivePresenterId, 'grace');
      expect(moved.isLocalPresenter, isFalse);
      expect(moved.presenter, grace);
      expect(state(me: 'grace', presenterId: 'grace').isLocalPresenter, isTrue);
    });
  });

  group('SchematicCollabPresenterView', () {
    const camera = SchematicCollabCamera(centerX: 1, centerY: 2, zoom: 3);
    const trace = SchematicCollabTrace(
      mode: 'fanout',
      cellIds: {'a'},
      edgeIds: {'e'},
      boundaryPortIds: {'port:p'},
    );

    test('compares by value, ids as sets', () {
      expect(
        const SchematicCollabPresenterView(
          scopePath: 'u_cpu',
          camera: camera,
          trace: trace,
        ),
        const SchematicCollabPresenterView(
          scopePath: 'u_cpu',
          camera: SchematicCollabCamera(centerX: 1, centerY: 2, zoom: 3),
          trace: SchematicCollabTrace(
            mode: 'fanout',
            cellIds: {'a'},
            edgeIds: {'e'},
            boundaryPortIds: {'port:p'},
          ),
        ),
      );
      expect(
        const SchematicCollabPresenterView(scopePath: 'u_cpu', camera: camera),
        isNot(const SchematicCollabPresenterView(scopePath: 'u_cpu')),
      );
    });

    test('a trace names every id it lights', () {
      expect(trace.allIds, {'a', 'e', 'port:p'});
    });
  });

  group('copyWith', () {
    test('carries and clears the presenter view', () {
      const view = SchematicCollabPresenterView(scopePath: '');
      final withView = state().copyWith(
        presenterView: view,
        presenterId: 'grace',
        pendingControlRequests: ['grace'],
      );
      expect(withView.presenterView, view);
      expect(withView.presenterId, 'grace');
      expect(withView.pendingControlRequests, ['grace']);
      expect(withView.copyWith(clearPresenterView: true).presenterView, isNull);
      expect(withView, isNot(state()));
    });
  });
}
