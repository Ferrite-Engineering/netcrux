// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/schematic_collaboration_service.dart';
import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';

/// Riverpod provider exposing the active [SchematicCollaborationService].
///
/// Open core resolves it to [NoopSchematicCollaborationService]; the Pro
/// overlay overrides it in `proOverrides`. Declared as a manual [Provider]
/// rather than codegen so the override needs no build_runner dependency —
/// matching [xTraceServiceProvider] and [coneOfInfluenceServiceProvider].
final schematicCollaborationServiceProvider =
    Provider<SchematicCollaborationService>(
      (ref) => const NoopSchematicCollaborationService(),
      name: 'schematicCollaborationServiceProvider',
    );

/// The live session snapshot, or `null` when no session is running.
///
/// A [StreamProvider] over [SchematicCollaborationService.sessionState] so
/// widgets watch one thing. Open core's no-op yields an empty stream, so this
/// stays `null` for the whole life of an open-core build.
final schematicCollabSessionProvider =
    StreamProvider<SchematicCollabSessionState?>((ref) {
      final service = ref.watch(schematicCollaborationServiceProvider);
      return service.sessionState;
    }, name: 'schematicCollabSessionProvider');
