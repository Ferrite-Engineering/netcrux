// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/schematic_collaboration_service.dart';
import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';
import 'package:netcrux/services/collaboration/collaboration_available_provider.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';

/// A stand-in for a real (overlay) service: anything that is not the no-op.
class _FakeService implements SchematicCollaborationService {
  final controller = StreamController<SchematicCollabSessionState?>.broadcast();
  bool live = false;

  @override
  Stream<SchematicCollabSessionState?> get sessionState => controller.stream;

  @override
  bool get isInSession => live;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('collaborationAvailableProvider', () {
    test('is false in the open-source build, which binds the no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(collaborationAvailableProvider), isFalse);
    });

    test('is true where a real collaboration service is bound', () {
      final container = ProviderContainer(
        overrides: [
          schematicCollaborationServiceProvider.overrideWithValue(
            _FakeService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(collaborationAvailableProvider), isTrue);
    });
  });

  group('collabSessionLiveProvider', () {
    test('follows the service across a published snapshot', () async {
      final service = _FakeService();
      addTearDown(service.controller.close);
      final container = ProviderContainer(
        overrides: [
          schematicCollaborationServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(collabSessionLiveProvider, (_, _) {});
      addTearDown(sub.close);

      expect(sub.read(), isFalse);

      service.live = true;
      service.controller.add(
        const SchematicCollabSessionState(
          sessionId: 'ABC123',
          myParticipantId: 'me',
          hostId: 'me',
          mode: SchematicCollabMode.lan,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), isTrue);

      service.live = false;
      service.controller.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), isFalse);
    });
  });
}
