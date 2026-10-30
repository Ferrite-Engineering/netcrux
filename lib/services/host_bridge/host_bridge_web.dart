// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Web `HostBridgeChannel`: the `window.postMessage` transport between this
// build and a VS Code extension host.
//
// A small `dart:js_interop` surface and nothing else; what is exchanged lives
// in `host_bridge_messages.dart` and what is done with it in
// `editor_host_bridge.dart`. This file has three jobs: read the marker,
// receive frames, post frames.
//
// ### Two globals, both set by the extension's page shim
//
// `cruxEditorHost`: frozen `{kind, protocol}`, set in an inline `<head>` script
// before any tag that can load `main.dart.js`. That ordering is what makes the
// answer available synchronously at startup. An absent marker means no host.
// The user agent and the URL scheme are deliberately not consulted: a webview
// is free to imitate either.
//
// `cruxHostBridge`: `{postMessage(frame)}`, the outbound seam. It has to be the
// shim's, not ours: a webview hands out its API handle once and the shim
// already holds it for its diagnostics, so this file never asks for it, since a
// second request throws and the throw would land in app startup. When the seam
// is absent [canPost] is false and outbound frames are dropped.

import 'dart:async';
import 'dart:js_interop';

import 'package:netcrux/domain/enums/editor_host_kind.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart';
import 'package:netcrux/services/host_bridge/host_bridge_transport.dart';

// ── JS interop shape ─────────────────────────────────────────────────────────

@JS(kEditorHostMarkerGlobal)
external _EditorHostMarker? get _cruxEditorHost;

@JS(kEditorHostSeamGlobal)
external _HostPoster? get _cruxHostBridge;

@JS('addEventListener')
external void _addWindowListener(JSString type, JSFunction listener);

@JS('removeEventListener')
external void _removeWindowListener(JSString type, JSFunction listener);

@JS('location.origin')
external JSString? get _locationOrigin;

/// The frozen marker object. Both fields are read as `JSAny?` and converted
/// defensively: this is a value another script wrote, so a `String`-typed
/// binding would throw rather than report "not a host".
extension type _EditorHostMarker._(JSObject _) implements JSObject {
  external JSAny? get kind;
  external JSAny? get protocol;
}

extension type _HostPoster._(JSObject _) implements JSObject {
  external void postMessage(JSAny? frame);
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
  external JSAny? get origin;
}

/// Web transport over `window.postMessage`.
class HostBridgeChannel implements HostBridgeTransport {
  /// Creates the channel and, when an editor host is present, installs the
  /// `message` listener.
  ///
  /// Installing nothing in a plain browser tab is the first half of the
  /// security posture: a page that embeds this app in an iframe can post
  /// whatever it likes and there is no listener to receive it. The second half
  /// is [isTrustedOrigin], applied to every frame that does arrive.
  HostBridgeChannel({bool Function(String origin)? isTrustedOrigin})
    : _isTrustedOrigin = isTrustedOrigin ?? defaultTrustedOrigin {
    if (hostKind != EditorHostKind.none) _install();
  }

  /// Reads `globalThis.cruxEditorHost.kind`. Synchronous and side-effect free,
  /// so `bootstrap` can ask before it builds the root container.
  ///
  /// An absent marker, a marker whose `kind` is anything but
  /// [kEditorHostMarkerKindVscode], and a marker that is not an object all
  /// resolve to [EditorHostKind.none].
  static EditorHostKind detectHostKind() {
    try {
      final marker = _cruxEditorHost;
      if (marker == null) return EditorHostKind.none;
      if (marker.kind.dartify() != kEditorHostMarkerKindVscode) {
        return EditorHostKind.none;
      }
      return EditorHostKind.vscode;
    } on Object {
      return EditorHostKind.none;
    }
  }

  /// Whether a frame from [origin] may be acted on.
  ///
  /// Inside a webview the origins in play are the editor's own
  /// (`vscode-webview://<id>`) and the document's; an empty origin is what a
  /// same-document `postMessage` reports. Anything else is a page that is not
  /// the host.
  static bool defaultTrustedOrigin(String origin) {
    if (origin.isEmpty) return true;
    if (origin.startsWith('vscode-webview://')) return true;
    return origin == _locationOrigin?.toDart;
  }

  final bool Function(String origin) _isTrustedOrigin;
  final StreamController<Map<String, Object?>> _controller =
      StreamController<Map<String, Object?>>.broadcast();
  JSFunction? _messageListener;

  @override
  EditorHostKind get hostKind => detectHostKind();

  @override
  bool get canPost =>
      hostKind != EditorHostKind.none && _cruxHostBridge != null;

  @override
  Stream<Map<String, Object?>> get inbound => _controller.stream;

  void _install() {
    final listener = ((_MessageEvent event) {
      try {
        final origin = event.origin.dartify();
        if (origin is! String || !_isTrustedOrigin(origin)) return;
        final frame = hostBridgeStringMap(event.data.dartify());
        if (frame == null) return;
        if (!_controller.isClosed) _controller.add(frame);
      } on Object {
        // Untrusted input must never throw into the app. A frame that cannot
        // be shape-checked is dropped, like one that fails the check.
      }
    }).toJS;
    _messageListener = listener;
    _addWindowListener('message'.toJS, listener);
  }

  @override
  void post(Map<String, Object?> frame) {
    if (!canPost) return;
    try {
      _cruxHostBridge?.postMessage(frame.jsify());
    } on Object {
      // A dead webview, a frozen seam, a value that will not clone: none of
      // them may surface in a feature flow.
    }
  }

  @override
  void dispose() {
    final listener = _messageListener;
    if (listener != null) {
      _removeWindowListener('message'.toJS, listener);
      _messageListener = null;
    }
    unawaited(_controller.close());
  }
}
