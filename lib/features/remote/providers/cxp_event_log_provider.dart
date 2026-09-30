// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';

/// Direction of a cross-probe event from this peer's point of view.
enum CxpEventDirection {
  /// We sent a message to a peer.
  outbound,

  /// We received a message from a peer.
  inbound,

  /// A discovery presence event (peer arrived / departed).
  presence,
}

/// One entry in the rolling cross-probe event log shown in the panel.
@immutable
class CxpEventLogEntry {
  /// Creates an entry.
  const CxpEventLogEntry({
    required this.timestamp,
    required this.direction,
    required this.kind,
    required this.peerLabel,
    this.detail,
  });

  /// Wall-clock time the event was observed.
  final DateTime timestamp;

  /// Direction (outbound / inbound / presence).
  final CxpEventDirection direction;

  /// Short kind label — the CXP message-kind discriminator for
  /// outbound/inbound entries, or `connected` / `disconnected` for
  /// presence entries.
  final String kind;

  /// Human-readable identifier for the peer involved (peer id +
  /// product name where available).
  final String peerLabel;

  /// Optional free-form detail line (display name of a selection,
  /// element path, etc.).
  final String? detail;

  @override
  String toString() =>
      'CxpEventLogEntry($direction $kind from/to $peerLabel @ $timestamp)';
}

/// Maximum entries retained in the rolling buffer. Older entries fall
/// off the end as new events arrive.
const int kCxpEventLogCapacity = 50;

/// Rolling cross-probe event log (newest-first). Combines inbound message
/// events and presence events observed on the running CXP server with the
/// **outbound** sends the panel's per-peer send, the automatic emitter, and
/// the "Open in WaveCrux" direct action record explicitly.
///
/// A [Notifier] (not a derived stream) so the shared cross-probe panel's
/// "Clear events" affordance can empty it ([clear]) and so outbound sends —
/// which no server stream reports — can be [recordOutbound]ed into the same
/// buffer. Rebuilds (dropping the buffer) whenever the server is
/// created/destroyed, matching the pre-increment stream's reset-on-restart
/// behaviour.
class CxpEventLogNotifier extends Notifier<List<CxpEventLogEntry>> {
  @override
  List<CxpEventLogEntry> build() {
    final serverAsync = ref.watch(cxpServerHostProvider);
    final liveServer = serverAsync.value?.server;
    if (liveServer == null) return const <CxpEventLogEntry>[];

    final inboundSub = liveServer.inbound.listen((m) {
      _push(
        CxpEventLogEntry(
          timestamp: DateTime.now(),
          direction: CxpEventDirection.inbound,
          kind: m.message.kind,
          peerLabel: '${m.from.productName} (${m.from.peerId})',
          detail: _detailForMessage(m.message),
        ),
      );
    });
    final presenceSub = liveServer.presence.listen((event) {
      _push(
        CxpEventLogEntry(
          timestamp: DateTime.now(),
          direction: CxpEventDirection.presence,
          kind: event.connected ? 'connected' : 'disconnected',
          peerLabel: '${event.peer.productName} (${event.peer.peerId})',
        ),
      );
    });
    ref.onDispose(() {
      unawaited(inboundSub.cancel());
      unawaited(presenceSub.cancel());
    });
    return const <CxpEventLogEntry>[];
  }

  /// Records an outbound send (a `notify_selection` / `request_highlight`
  /// this app dispatched) — the server reports only inbound + presence, so
  /// outbound rows are recorded at the send site.
  void recordOutbound({
    required String kind,
    required String peerLabel,
    String? detail,
  }) => _push(
    CxpEventLogEntry(
      timestamp: DateTime.now(),
      direction: CxpEventDirection.outbound,
      kind: kind,
      peerLabel: peerLabel,
      detail: detail,
    ),
  );

  /// Empties the buffer (the shared panel's "Clear events" affordance).
  void clear() => state = const <CxpEventLogEntry>[];

  void _push(CxpEventLogEntry entry) {
    final next = <CxpEventLogEntry>[entry, ...state];
    if (next.length > kCxpEventLogCapacity) {
      next.removeRange(kCxpEventLogCapacity, next.length);
    }
    state = List<CxpEventLogEntry>.unmodifiable(next);
  }

  static String? _detailForMessage(CxpMessage message) {
    return switch (message) {
      NotifySelection(:final elements, :final displayName) =>
        displayName ?? elements.first.path,
      RequestHighlight(:final element) => element.path,
      RequestOpenSource(:final filePath, :final line) => '$filePath:$line',
      RequestOpenArtifact(:final artifactKind, :final designId) =>
        '$artifactKind · $designId',
      _ => null,
    };
  }
}

/// The rolling cross-probe event log. See [CxpEventLogNotifier].
final cxpEventLogProvider =
    NotifierProvider<CxpEventLogNotifier, List<CxpEventLogEntry>>(
      CxpEventLogNotifier.new,
      name: 'cxpEventLogProvider',
    );
