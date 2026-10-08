// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Open-core extension point for Enterprise-tier collaborative schematic
/// sessions.
///
/// Open core ships [NoopSchematicCollaborationService] as the default — no
/// network calls, no dependencies, every query returns a neutral value. The
/// closed-source Pro overlay replaces the binding through
/// `schematicCollaborationServiceProvider` with an implementation that runs
/// real WebSocket sessions (LAN direct, or WAN through a relay).
///
/// **The provider lives in `services/collaboration/`, not here.** `domain/` is
/// hermetic — no Flutter, no Riverpod (ARCHITECTURE.md §6.2) — so the contract
/// and the binding that publishes it are two files by rule rather than by
/// preference. `x_trace_service.dart` and its provider are the precedent.
///
/// Callers must never assume the implementation is network-capable. Every
/// interactive entry point routes through `FeatureGate.isAvailable` with
/// `LicenseTier.enterprise`, so Open Core and Pro builds are unaffected while
/// the no-op is active.
///
/// **The protocol is WaveCrux's.** Admission control and end-to-end
/// encryption for WAN are ported, not redesigned: the invite carries key
/// material the relay never sees, so authentication falls out of encryption
/// with no accounts and no directory, and a `hello` is a *request* rather than
/// the act of joining.
library;

import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';

/// Runs collaborative schematic sessions.
///
/// Implementations never throw to the caller: a relay that is unreachable, a
/// LAN host that is not there, or an invite that does not parse all resolve
/// through [lastJoinOutcome] and the [sessionState] stream. A network failure
/// is a thing to report in the UI, not an exception to propagate through a
/// button handler.
abstract interface class SchematicCollaborationService {
  /// Broadcasts a snapshot on every roster, cursor, selection or admission
  /// change, then a **terminal `null`** when the session ends.
  ///
  /// That `null` is not decoration. A `StreamProvider` retains its last
  /// `AsyncData` when a stream merely stops emitting, so a session that ended
  /// without saying so leaves every consumer rendering it: departed peers'
  /// selections still outlined on the canvas, the status-bar chip still
  /// counting participants in a room nobody is in. Leaving, being dropped and
  /// a failed create/join all emit it.
  Stream<SchematicCollabSessionState?> get sessionState;

  /// Whether a session is currently running (including one where the local
  /// participant is still awaiting admission).
  bool get isInSession;

  /// The current network mode, or [SchematicCollabMode.none] outside a
  /// session.
  SchematicCollabMode get mode;

  /// How the most recent [joinSession] attempt ended.
  SchematicCollabJoinOutcome get lastJoinOutcome;

  /// The invite string to hand to the people being invited — `ROOM-<secret>`
  /// for WAN, or the LAN host address for LAN. Empty outside a session.
  ///
  /// **Only the room half ever reaches the relay.** The secret half is key
  /// material; treat the whole string as a credential.
  String get invite;

  /// Starts hosting a session in [mode] and returns `true` when it came up.
  ///
  /// The host admits itself, so it is immediately
  /// [SchematicCollabAdmission.approved].
  Future<bool> createSession({
    required SchematicCollabMode mode,
    required String displayName,
  });

  /// Joins the session named by [invite].
  ///
  /// Returns `true` once the transport is up and the announcement has been
  /// sent — **not** that the host has admitted us. Admission resolves
  /// asynchronously; watch [sessionState] for
  /// [SchematicCollabSessionState.admission] and read [lastJoinOutcome] when
  /// it does.
  ///
  /// [lanHost] is the manual-IP fallback for networks where mDNS is blocked.
  Future<bool> joinSession({
    required String invite,
    required String displayName,
    SchematicCollabMode mode = SchematicCollabMode.wan,
    String? lanHost,
  });

  /// Leaves the session, says goodbye and tears the transport down. Safe to
  /// call when not in a session.
  Future<void> leaveSession();

  /// Host-only: admit or refuse the joiner with [participantId].
  void respondToJoinRequest(String participantId, {required bool approve});

  /// Publishes the local pointer position in **design space** for the scope at
  /// [scopePath], or clears it when [x] and [y] are `null` (pointer left the
  /// canvas).
  ///
  /// Throttled by the implementation; call it as often as the gesture handler
  /// produces positions.
  void updateCursor({required String scopePath, double? x, double? y});

  /// Publishes the local selection for the scope at [scopePath].
  void updateSelection({
    required String scopePath,
    required Set<String> elementIds,
  });

  /// Announces which scope this participant is viewing, and the digest of the
  /// design they have open.
  ///
  /// The digest is how a room notices it is looking at two different
  /// elaborations of the same design — the commonest way a review goes
  /// sideways. Only the digest crosses the wire.
  void announceScope({required String scopePath, String? netlistContentHash});

  /// Follow [participantId]'s scope changes, or stop following when `null`.
  void setFollowTarget(String? participantId);

  // ── presenter mode ─────────────────────────────────────────────────────────
  //
  // One presenter at a time, and everyone else follows what they show. The
  // host starts as presenter; the token moves only by an explicit handoff or
  // a granted request, and the host is the single arbiter, so two transfers
  // can never race. When the presenter drops the host reclaims the token;
  // when the host drops the longest-standing participant becomes host and
  // presenter. None of this carries a tier: a guest without a licence asks to
  // present, presents and follows like anyone else.

  /// Hands the presenter token to [participantId]. Honoured from the current
  /// presenter or the host.
  void handoffPresenter(String participantId);

  /// Asks the host (or the presenter) for the presenter token. A host simply
  /// takes it back.
  void requestPresenter();

  /// Grants or denies [participantId]'s request to present. Honoured from the
  /// current presenter or the host.
  void respondToPresenterRequest(String participantId, {required bool grant});

  /// Publishes what the local participant is showing. Ignored by everyone
  /// else unless the local participant holds the presenter token.
  void updatePresenterView(SchematicCollabPresenterView view);

  /// Clears the "somebody in this room is holding the wrong invite" notice.
  void dismissUnreadableFramesNotice();

  /// Releases every resource. The service is unusable afterwards.
  Future<void> dispose();
}

/// Open-core default: a service that is never in a session.
///
/// Every method is a no-op and every query returns the neutral value, so the
/// call sites above it — the gesture handler publishing a cursor, the
/// selection notifier publishing a selection — run unchanged in a build with
/// no Pro overlay. That is deliberate: a seam only exercised in one build is a
/// seam that breaks in the other.
final class NoopSchematicCollaborationService
    implements SchematicCollaborationService {
  /// Creates the no-op service.
  const NoopSchematicCollaborationService();

  @override
  Stream<SchematicCollabSessionState?> get sessionState =>
      const Stream<SchematicCollabSessionState?>.empty();

  @override
  bool get isInSession => false;

  @override
  SchematicCollabMode get mode => SchematicCollabMode.none;

  @override
  SchematicCollabJoinOutcome get lastJoinOutcome =>
      SchematicCollabJoinOutcome.none;

  @override
  String get invite => '';

  @override
  Future<bool> createSession({
    required SchematicCollabMode mode,
    required String displayName,
  }) async => false;

  @override
  Future<bool> joinSession({
    required String invite,
    required String displayName,
    SchematicCollabMode mode = SchematicCollabMode.wan,
    String? lanHost,
  }) async => false;

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
  void handoffPresenter(String participantId) {}

  @override
  void requestPresenter() {}

  @override
  void respondToPresenterRequest(
    String participantId, {
    required bool grant,
  }) {}

  @override
  void updatePresenterView(SchematicCollabPresenterView view) {}

  @override
  void dismissUnreadableFramesNotice() {}

  @override
  Future<void> dispose() async {}
}
