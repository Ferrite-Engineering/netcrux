// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Non-web stub for `HostBridgeChannel`.
//
// An editor host can only exist on the web build, where the extension pack
// hosts the app in a webview, so on desktop and in the VM test runner there is
// nothing on the other end of the bridge. This stub says so: no host, no
// inbound frames, nothing posted. It does not throw, because the off-web case
// is the common one and "there is no editor host" is the useful answer.

import 'package:netcrux/domain/enums/editor_host_kind.dart';
import 'package:netcrux/services/host_bridge/host_bridge_transport.dart';

/// Inert channel for hosts with no `window.postMessage`.
class HostBridgeChannel implements HostBridgeTransport {
  /// Creates the inert channel. Installs nothing.
  HostBridgeChannel();

  /// Always [EditorHostKind.none] off the web.
  static EditorHostKind detectHostKind() => EditorHostKind.none;

  @override
  EditorHostKind get hostKind => EditorHostKind.none;

  @override
  bool get canPost => false;

  @override
  Stream<Map<String, Object?>> get inbound =>
      const Stream<Map<String, Object?>>.empty();

  @override
  void post(Map<String, Object?> frame) {}

  @override
  void dispose() {}
}
