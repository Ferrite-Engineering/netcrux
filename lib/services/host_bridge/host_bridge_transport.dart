// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The transport seam between this build and an editor extension host.
//
// It exists so the two halves of the bridge can be tested apart. The concrete
// channel (`window.postMessage` on the web, an inert stub everywhere else) is
// chosen by a conditional export and cannot be substituted, which would make
// every dispatch test a browser test. The bridge therefore depends on this
// interface, and the VM suite drives it through a fake.
//
// What the host and the app say to each other is decided in
// `host_bridge_messages.dart`, not here.

import 'package:netcrux/domain/enums/editor_host_kind.dart';

/// What the editor-host bridge needs from a transport.
abstract interface class HostBridgeTransport {
  /// The editor host on the other end, or [EditorHostKind.none]. Resolved
  /// synchronously: the marker it reads is set before the Dart entry point
  /// loads.
  EditorHostKind get hostKind;

  /// Whether outbound frames can reach the host. False in a plain browser tab
  /// and in a webview whose shim has not published the outbound seam.
  bool get canPost;

  /// Well-formed frames the host posted, in arrival order. Frames are
  /// untrusted: the maps are string-keyed and nothing more is checked.
  Stream<Map<String, Object?>> get inbound;

  /// Posts [frame] to the host. Never throws, and drops the frame when
  /// [canPost] is false.
  void post(Map<String, Object?> frame);

  /// Releases whatever the transport installed.
  void dispose();
}
