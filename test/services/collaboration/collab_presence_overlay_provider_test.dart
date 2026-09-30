// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/theme/collaborator_palette.dart';
import 'package:netcrux/domain/interfaces/schematic_collaboration_service.dart';
import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/collaboration/collab_presence_overlay_provider.dart';
import 'package:netcrux/features/collaboration/collab_presence_publisher.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';

/// A service whose session stream the test drives directly.
///
/// Implements the interface rather than extending the no-op, which is `final`
/// on purpose: open core's default is not an extension point, it is the answer
/// for a build with no overlay.
class _StubCollaborationService implements SchematicCollaborationService {
  _StubCollaborationService(this._controller);

  final StreamController<SchematicCollabSessionState> _controller;

  @override
  Stream<SchematicCollabSessionState> get sessionState => _controller.stream;

  @override
  bool get isInSession => true;

  @override
  SchematicCollabMode get mode => SchematicCollabMode.wan;

  @override
  SchematicCollabJoinOutcome get lastJoinOutcome =>
      SchematicCollabJoinOutcome.connected;

  @override
  String get invite => 'ROOM01-AAAAAAAAAAAAAAAAAAAAAA';

  @override
  Future<bool> createSession({
    required SchematicCollabMode mode,
    required String displayName,
  }) async => true;

  @override
  Future<bool> joinSession({
    required String invite,
    required String displayName,
    SchematicCollabMode mode = SchematicCollabMode.wan,
    String? lanHost,
  }) async => true;

  @override
  Future<void> leaveSession() async {}

  @override
  void respondToJoinRequest(String participantId, {required bool approve}) {}

  @override
  void updateCursor({required String scopePath, double? x, double? y}) {}

  @override
  void updateSelection({
    required String scopePath,
    required Set<String> elementIds,
  }) {}

  @override
  void announceScope({
    required String scopePath,
    String? netlistContentHash,
  }) {}

  @override
  void setFollowTarget(String? participantId) {}

  @override
  void dismissUnreadableFramesNotice() {}

  @override
  Future<void> dispose() async {}
}

/// The scope the local client is in.
///
/// Read back from the hierarchy through the app's own helper rather than
/// written out here: the wire format is `HierarchyNode.path` joined, and a test
/// that hard-codes its own join agrees with itself instead of with the app —
/// which is exactly how the `Object`-typed comparison this suite found stayed
/// invisible for as long as it did.
late String Function() localScope;

SchematicParticipantInfo _peer({
  required String id,
  required int colorIndex,
  String? scopePath,
  double? x,
  double? y,
  Set<String> selection = const <String>{},
}) => SchematicParticipantInfo(
  id: id,
  displayName: id,
  colorIndex: colorIndex,
  isHost: false,
  scopePath: scopePath ?? localScope(),
  cursorX: x,
  cursorY: y,
  selectedElementIds: selection,
);

SchematicCollabSessionState _session(
  List<SchematicParticipantInfo> participants, {
  SchematicCollabAdmission admission = SchematicCollabAdmission.approved,
}) => SchematicCollabSessionState(
  sessionId: 'ROOM01',
  myParticipantId: 'me',
  hostId: 'me',
  mode: SchematicCollabMode.wan,
  participants: participants,
  admission: admission,
);

void main() {
  late StreamController<SchematicCollabSessionState> controller;
  late ProviderContainer container;

  setUp(() {
    controller = StreamController<SchematicCollabSessionState>.broadcast();
    localScope = () =>
        collabScopePath(container.read(hierarchyTreeProvider).selected);
    container =
        ProviderContainer(
            overrides: [
              schematicCollaborationServiceProvider.overrideWithValue(
                _StubCollaborationService(controller),
              ),
            ],
          )
          // Keep the stream provider alive so an emission is observed.
          ..listen(schematicCollabSessionProvider, (_, _) {})
          // A one-module design, so the hierarchy has a real selected scope
          // to compare against — the overlay's scope filter is what half
          // these cases are testing.
          ..read(hierarchyTreeProvider.notifier).setModel(
            const NetlistModel(
              creator: 'test',
              modules: {
                'top': Module(
                  name: 'top',
                  attributes: {'top': '00000000000000000000000000000001'},
                  ports: {},
                  cells: {},
                  nets: {},
                ),
              },
            ),
          );
  });

  tearDown(() {
    container.dispose();
    return controller.close();
  });

  Future<CollabPresenceOverlay?> overlayFor(
    SchematicCollabSessionState state,
  ) async {
    controller.add(state);
    // The stream provider republishes on an event-loop turn, not a microtask.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return container.read(collabPresenceOverlayProvider);
  }

  test('no session paints nothing', () {
    expect(container.read(collabPresenceOverlayProvider), isNull);
  });

  test('the local participant never draws their own cursor', () async {
    final overlay = await overlayFor(
      _session([
        _peer(id: 'me', colorIndex: 3, x: 1, y: 1),
      ]),
    );
    expect(
      overlay,
      isNull,
      reason: 'you already know where your own pointer is',
    );
  });

  test('a peer in another scope contributes nothing', () async {
    final overlay = await overlayFor(
      _session([
        _peer(
          id: 'grace',
          colorIndex: 1,
          scopePath: 'somewhere/else',
          x: 4,
          y: 5,
        ),
      ]),
    );
    expect(
      overlay,
      isNull,
      reason:
          'the same (x, y) is two unrelated places in two modules, so a '
          'cross-scope cursor would point at the wrong gate',
    );
  });

  test('a peer in this scope draws a cursor in their palette colour', () async {
    final overlay = await overlayFor(
      _session([
        _peer(id: 'grace', colorIndex: 2, x: 7, y: 8),
      ]),
    );
    expect(overlay!.cursors, hasLength(1));
    expect(overlay.cursors.single.x, 7);
    expect(overlay.cursors.single.y, 8);
    expect(overlay.cursors.single.color, collaboratorColor(2));
  });

  test('two peers on one element resolve to the lower colour index', () async {
    final overlay = await overlayFor(
      _session([
        _peer(id: 'grace', colorIndex: 5, selection: {'u_fifo'}),
        _peer(id: 'alan', colorIndex: 1, selection: {'u_fifo'}),
      ]),
    );
    expect(
      overlay!.selectionColors['u_fifo'],
      collaboratorColor(1),
      reason:
          'a stable winner, so the outline does not flicker between two '
          'colours as snapshots arrive',
    );
  });

  test(
    'an unadmitted client renders no room it has not been let into',
    () async {
      final overlay = await overlayFor(
        _session(
          [_peer(id: 'grace', colorIndex: 1, x: 1, y: 1)],
          admission: SchematicCollabAdmission.awaitingApproval,
        ),
      );
      expect(overlay, isNull);
    },
  );
}
