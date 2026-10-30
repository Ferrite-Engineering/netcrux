// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:netcrux/domain/enums/editor_host_kind.dart';
import 'package:netcrux/services/host_bridge/host_bridge_transport.dart';

/// A transport a test drives by hand: [receive] is the editor host posting a
/// frame, [posted] is everything the app posted back.
class FakeHostBridgeTransport implements HostBridgeTransport {
  /// Creates a transport that reports [hostKind] and, when [canPost], records
  /// what is posted.
  FakeHostBridgeTransport({
    this.hostKind = EditorHostKind.vscode,
    this.canPost = true,
  });

  final StreamController<Map<String, Object?>> _inbound =
      StreamController<Map<String, Object?>>.broadcast();

  /// Frames the app posted, oldest first.
  final List<Map<String, Object?>> posted = <Map<String, Object?>>[];

  @override
  final EditorHostKind hostKind;

  @override
  final bool canPost;

  @override
  Stream<Map<String, Object?>> get inbound => _inbound.stream;

  /// Delivers [frame] to the app as if the host had posted it.
  void receive(Map<String, Object?> frame) => _inbound.add(frame);

  @override
  void post(Map<String, Object?> frame) {
    if (canPost) posted.add(frame);
  }

  @override
  void dispose() => unawaited(_inbound.close());
}
