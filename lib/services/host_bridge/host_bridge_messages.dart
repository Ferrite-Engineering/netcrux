// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// What an editor extension host and this build say to each other.
//
// Every frame is a flat string-keyed map: `{type: 'crux.netcrux', protocol: 1,
// kind: '<kind>', ...fields}`. The `type` lets the extension tell these frames
// from the page shim's own diagnostics, and `protocol` is bumped only when a
// field changes meaning; an unknown kind or an unknown field is ignored, so a
// newer host can talk to an older build.
//
// Frames arrive on `window.postMessage` and are untrusted. Parsing validates
// the shape of everything it reads and returns null for anything else; nothing
// here throws.
//
// ### Host to app
//
// - `open_netlist {name, text, scope?, signal?}`: show the Yosys JSON netlist
//   in [text] in a tab labelled [name], then apply the optional `#scope=` /
//   `#sig=` style hints the browser deep link carries.
// - `theme_tokens {appearance, tokens}`: the editor's resolved colors, read by
//   the page shim from the `--vscode-*` custom properties.
//
// ### App to host
//
// - `ready {}`: the listener is installed; a frame sent earlier would be lost.
// - `open_source {file, line, column?}`: show a source location in the
//   editor.
// - `status {phase, message?, modules?, cells?}`: progress of the document,
//   for the extension's log.

import 'package:meta/meta.dart';

/// The global the extension's page shim publishes, frozen, before
/// `main.dart.js` runs: `{kind, protocol}`. Absent when nothing hosts this
/// build. Both halves of the contract read this name, so it is a constant on
/// each side with a test pinning it.
const String kEditorHostMarkerGlobal = 'cruxEditorHost';

/// The global the shim publishes for outbound frames: `{postMessage(frame)}`.
///
/// The shim owns the editor's API handle, which a webview hands out once, so
/// the app posts through this object and never acquires the handle itself.
const String kEditorHostSeamGlobal = 'cruxHostBridge';

/// The global the shim publishes with the URL of the layout worker it staged
/// for this webview, when it could (a string), or leaves undefined.
///
/// A webview's resources are served from a different origin than its
/// document, and a browser refuses to start a worker from another origin, so
/// the shim fetches the worker's files and starts it from a blob URL instead.
const String kEditorHostLayoutWorkerGlobal = 'cruxLayoutWorkerUrl';

/// `cruxEditorHost.kind` for a VS Code extension host.
const String kEditorHostMarkerKindVscode = 'vscode';

/// `type` of every frame crossing the bridge, in both directions.
const String kHostBridgeFrameType = 'crux.netcrux';

/// The protocol version this build speaks.
const int kHostBridgeProtocolVersion = 1;

/// The largest netlist text accepted, in UTF-16 code units. The extension
/// refuses a file well below this before sending it; this is the receiver's
/// own bound, so a hostile or buggy sender cannot make the page build a string
/// the engine cannot hold.
const int kHostBridgeMaxNetlistChars = 256 * 1024 * 1024;

/// The longest tab label accepted.
const int kHostBridgeMaxNameChars = 512;

/// The longest scope or signal hint accepted.
const int kHostBridgeMaxHintChars = 4096;

/// Host to app: open a netlist.
const String kHostBridgeOpenNetlistKind = 'open_netlist';

/// Host to app: the editor's colors.
const String kHostBridgeThemeTokensKind = 'theme_tokens';

/// App to host: the listener is installed.
const String kHostBridgeReadyKind = 'ready';

/// App to host: show a source location.
const String kHostBridgeOpenSourceKind = 'open_source';

/// App to host: progress of the document.
const String kHostBridgeStatusKind = 'status';

/// The theme appearances the shim reports, mirroring VS Code's color theme
/// kinds.
const Set<String> kHostBridgeThemeAppearances = <String>{
  'light',
  'dark',
  'highContrast',
  'highContrastLight',
};

/// A frame the host sent.
@immutable
sealed class HostBridgeInbound {
  const HostBridgeInbound();
}

/// Open the netlist in [text], labelled [name].
@immutable
final class HostBridgeOpenNetlist extends HostBridgeInbound {
  /// Creates the request.
  const HostBridgeOpenNetlist({
    required this.name,
    required this.text,
    this.scope,
    this.signal,
  });

  /// The tab label, normally the file's base name. Ends in `.json` so the
  /// loader classifies the document as a netlist.
  final String name;

  /// The whole Yosys JSON document.
  final String text;

  /// The dotted scope path to open, as the `#scope=` hint of a web link.
  final String? scope;

  /// The net or cell to select, as the `#sig=` hint of a web link.
  final String? signal;

  @override
  bool operator ==(Object other) =>
      other is HostBridgeOpenNetlist &&
      other.name == name &&
      other.text == text &&
      other.scope == scope &&
      other.signal == signal;

  @override
  int get hashCode => Object.hash(name, text, scope, signal);
}

/// The editor's resolved colors.
@immutable
final class HostBridgeThemeTokens extends HostBridgeInbound {
  /// Creates the frame.
  const HostBridgeThemeTokens({
    required this.appearance,
    required this.tokens,
  });

  /// One of [kHostBridgeThemeAppearances].
  final String appearance;

  /// Color value (`#RRGGBB` or `#RRGGBBAA`) by VS Code's dotted color id.
  final Map<String, String> tokens;
}

/// Decodes [frame], or returns null when it is not a well-formed frame of a
/// kind this build understands.
HostBridgeInbound? parseHostBridgeFrame(Map<String, Object?> frame) {
  if (frame['type'] != kHostBridgeFrameType) return null;
  final protocol = frame['protocol'];
  if (protocol is! num || protocol.toInt() < 1) return null;
  return switch (frame['kind']) {
    kHostBridgeOpenNetlistKind => _parseOpenNetlist(frame),
    kHostBridgeThemeTokensKind => _parseThemeTokens(frame),
    _ => null,
  };
}

HostBridgeOpenNetlist? _parseOpenNetlist(Map<String, Object?> frame) {
  final name = frame['name'];
  final text = frame['text'];
  if (name is! String || name.isEmpty) return null;
  if (name.length > kHostBridgeMaxNameChars) return null;
  if (text is! String || text.isEmpty) return null;
  if (text.length > kHostBridgeMaxNetlistChars) return null;
  return HostBridgeOpenNetlist(
    name: name,
    text: text,
    scope: _hint(frame['scope']),
    signal: _hint(frame['signal']),
  );
}

String? _hint(Object? value) {
  if (value is! String || value.isEmpty) return null;
  if (value.length > kHostBridgeMaxHintChars) return null;
  return value;
}

HostBridgeThemeTokens? _parseThemeTokens(Map<String, Object?> frame) {
  final appearance = frame['appearance'];
  final raw = frame['tokens'];
  if (appearance is! String ||
      !kHostBridgeThemeAppearances.contains(appearance)) {
    return null;
  }
  if (raw is! Map) return null;
  final tokens = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is String && value is String) tokens[key] = value;
  }
  return HostBridgeThemeTokens(appearance: appearance, tokens: tokens);
}

/// Coerces a decoded `postMessage` payload to a string-keyed map, or null when
/// it is not an object.
Map<String, Object?>? hostBridgeStringMap(Object? raw) {
  if (raw is! Map) return null;
  final out = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) return null;
    out[key] = entry.value;
  }
  return out;
}

Map<String, Object?> _frame(String kind, Map<String, Object?> fields) =>
    <String, Object?>{
      'type': kHostBridgeFrameType,
      'protocol': kHostBridgeProtocolVersion,
      'kind': kind,
      ...fields,
    };

/// The frame announcing that the listener is installed.
Map<String, Object?> hostBridgeReadyFrame() =>
    _frame(kHostBridgeReadyKind, const <String, Object?>{});

/// The frame asking the editor to show [file] at [line] (1-based) and
/// [column] (1-based, when known).
Map<String, Object?> hostBridgeOpenSourceFrame({
  required String file,
  required int line,
  int? column,
}) => _frame(kHostBridgeOpenSourceKind, <String, Object?>{
  'file': file,
  'line': line,
  'column': ?column,
});

/// What a [hostBridgeStatusFrame] reports.
enum HostBridgeStatusPhase {
  /// The document was received and is being read and laid out.
  loading,

  /// The document opened.
  loaded,

  /// The document could not be opened.
  failed,
}

/// The frame reporting where the document stands.
Map<String, Object?> hostBridgeStatusFrame(
  HostBridgeStatusPhase phase, {
  String? message,
  int? modules,
  int? cells,
}) => _frame(kHostBridgeStatusKind, <String, Object?>{
  'phase': phase.name,
  'message': ?message,
  'modules': ?modules,
  'cells': ?cells,
});
