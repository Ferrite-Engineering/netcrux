// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cxp_dial_failures_provider.g.dart';

/// Streams the set of discovered-but-unreachable peers — peers whose
/// manifest the connector found but whose server it could not dial.
///
/// This is the product-facing surface for `CxpPeerConnector.dialFailures`,
/// which is otherwise consumed nowhere and leaves one-way connectivity
/// invisible. The panel `ref.watch`es this provider and renders a
/// persistent warning row per entry.
///
/// Each yielded list is a fresh snapshot of the connector's per-peer
/// failure map, re-emitted on every signal that can change it:
///
/// - a fresh dial failure adds or refreshes an entry (`dialFailures`);
/// - a discovery add/remove changes the peer set — a removed manifest
///   drops its failure entry (`discovery.events`);
/// - an inbound presence event means a peer connected, so a peer that was
///   unreachable and is now reachable drops out of the map
///   (`server.presence`).
///
/// The three sources are merged through one controller so a single
/// `await for` drives the panel.
@Riverpod(keepAlive: true)
Stream<List<CxpDialFailure>> cxpDialFailures(Ref ref) async* {
  final serverAsync = ref.watch(cxpServerHostProvider);
  final server = serverAsync.value;
  final failures = server?.dialFailures;
  if (server == null || failures == null) {
    yield const <CxpDialFailure>[];
    return;
  }

  final controller = StreamController<void>();
  final failureSub = failures.listen((_) => controller.add(null));
  final discoverySub = server.discovery?.events.listen(
    (_) => controller.add(null),
  );
  final presenceSub = server.server?.presence.listen(
    (_) => controller.add(null),
  );
  ref.onDispose(() {
    unawaited(failureSub.cancel());
    unawaited(discoverySub?.cancel());
    unawaited(presenceSub?.cancel());
    unawaited(controller.close());
  });

  yield server.unreachablePeers;
  await for (final _ in controller.stream) {
    yield server.unreachablePeers;
  }
}
