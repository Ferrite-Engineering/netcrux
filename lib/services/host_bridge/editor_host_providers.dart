// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/enums/editor_host_kind.dart';
import 'package:netcrux/services/host_bridge/editor_host_bridge.dart';
import 'package:netcrux/services/host_bridge/host_bridge.dart';
import 'package:netcrux/services/host_bridge/host_bridge_transport.dart';

/// Which editor, if any, hosts this build.
///
/// The default is [EditorHostKind.none]; `bootstrap` overrides it with the
/// answer the page shim's marker gives, read before the root container exists
/// so every dependent can decide synchronously. Declared as a manual
/// `Provider` so a test overrides it without code generation.
final editorHostKindProvider = Provider<EditorHostKind>(
  (_) => EditorHostKind.none,
  name: 'editorHostKindProvider',
);

/// Whether an editor hosts this build.
final isEditorHostedProvider = Provider<bool>(
  (ref) => ref.watch(editorHostKindProvider) != EditorHostKind.none,
  name: 'isEditorHostedProvider',
);

/// The transport to the editor host: `window.postMessage` on the web, an inert
/// stub elsewhere. Typed to the interface so a test can substitute a fake.
final hostBridgeChannelProvider = Provider<HostBridgeTransport>((ref) {
  final channel = HostBridgeChannel();
  ref.onDispose(channel.dispose);
  return channel;
}, name: 'hostBridgeChannelProvider');

/// The bridge itself. Reading it starts it; `bootstrap` reads it once so an
/// extension host can drive the build from the first frame.
final editorHostBridgeProvider = Provider<EditorHostBridge>((ref) {
  final bridge = EditorHostBridge(
    ref: ref,
    channel: ref.watch(hostBridgeChannelProvider),
  )..start();
  ref.onDispose(bridge.dispose);
  return bridge;
}, name: 'editorHostBridgeProvider');
