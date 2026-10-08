// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/schematic_collaboration_service.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';

/// Whether this build can actually take part in a collaborative session.
///
/// True only when [schematicCollaborationServiceProvider] is bound to a real
/// service (the open-source build binds [NoopSchematicCollaborationService])
/// and this is not the browser build, which has no sockets to run a session
/// on.
///
/// Join Session is free in every edition, so unlike Share Session it carries
/// no tier badge, and the rule that hides tier-badged actions in the browser
/// does not cover it. This is the capability test that keeps a Join action from
/// being offered where it would do nothing.
final collaborationAvailableProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      ref.watch(schematicCollaborationServiceProvider)
          is! NoopSchematicCollaborationService,
  name: 'collaborationAvailableProvider',
);

/// Whether a collaborative session is live, including a join still waiting for
/// the host's decision.
///
/// Read from the service rather than from the session stream: a joiner at the
/// door has a transport up (so Leave must work) before the first snapshot
/// arrives, and the stream is what the service publishes, so the two agree
/// from the first emission on.
final collabSessionLiveProvider = Provider<bool>((ref) {
  // Rebuilds on every published snapshot, including the terminal null.
  ref.watch(schematicCollabSessionProvider);
  return ref.watch(schematicCollaborationServiceProvider).isInSession;
}, name: 'collabSessionLiveProvider');
