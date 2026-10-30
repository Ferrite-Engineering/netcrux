// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The editor-host bridge: what an extension host can ask this build to do, and
// what this build tells it back.
//
// ### Untrusted input
//
// Frames arrive on `window.postMessage`. Everything below assumes the sender is
// hostile: the shape is validated before it is read, the netlist text is
// bounded, an unknown kind is dropped, and no path here throws.
//
// ### What each frame does
//
// - `open_netlist` is queued on `hostNetlistRequestProvider`. The workspace
//   screen opens it as a tab, because a tab needs a `BuildContext` and the
//   workspace's tab containers, which this root-scope object does not have.
// - `theme_tokens` is recorded on `hostThemeTokensProvider`. `bootstrap` turns
//   it into a session-only theme and applies it through
//   `NetcruxCruxColorThemeNotifier.applyEphemeral`, never `activate`: the
//   editor's colors must win immediately and follow every live theme change,
//   but must not overwrite the preset the user chose for the standalone app.
//
// The bridge announces `ready` once its listener is installed. The extension
// waits for it before sending the document, because a `postMessage` sent
// before any listener exists is lost, not queued.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/enums/editor_host_kind.dart';
import 'package:netcrux/domain/models/source_location.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart';
import 'package:netcrux/services/host_bridge/host_bridge_transport.dart';
import 'package:netcrux/services/host_bridge/host_netlist_request_provider.dart';
import 'package:netcrux/services/host_bridge/host_theme_tokens_provider.dart';

/// Drives this build from an editor extension host, and reports back to it.
///
/// Constructed once, at the root container, by `editorHostBridgeProvider`. On
/// every host but a webview the transport is the inert stub, so [start]
/// installs nothing and the object costs one allocation, which is why nothing
/// in the app has to ask whether it is hosted before wiring it up.
class EditorHostBridge {
  /// Creates a bridge over [_channel], mutating state through [_ref].
  EditorHostBridge({required this._ref, required this._channel});

  final Ref _ref;
  final HostBridgeTransport _channel;
  StreamSubscription<Map<String, Object?>>? _inboundSub;

  /// The editor host on the other end, or [EditorHostKind.none].
  EditorHostKind get hostKind => _channel.hostKind;

  /// Starts listening for the host's frames and announces `ready`.
  void start() {
    if (_inboundSub != null || _channel.hostKind == EditorHostKind.none) return;
    _inboundSub = _channel.inbound.listen(_dispatch);
    _channel.post(hostBridgeReadyFrame());
  }

  void _dispatch(Map<String, Object?> frame) {
    final message = parseHostBridgeFrame(frame);
    switch (message) {
      case null:
        return;
      case final HostBridgeOpenNetlist open:
        _ref.read(hostNetlistRequestProvider.notifier).submit(open);
      case final HostBridgeThemeTokens theme:
        _ref.read(hostThemeTokensProvider.notifier).submit(theme);
    }
  }

  /// Asks the editor to show [location]. Dropped when the host cannot be
  /// reached.
  void openSource(SourceLocation location) {
    _channel.post(
      hostBridgeOpenSourceFrame(
        file: location.filePath,
        line: location.line,
        column: location.column,
      ),
    );
  }

  /// Tells the editor where the document stands.
  void reportStatus(
    HostBridgeStatusPhase phase, {
    String? message,
    int? modules,
    int? cells,
  }) {
    _channel.post(
      hostBridgeStatusFrame(
        phase,
        message: message,
        modules: modules,
        cells: cells,
      ),
    );
  }

  /// Stops listening.
  void dispose() {
    unawaited(_inboundSub?.cancel());
    _inboundSub = null;
  }
}
