// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Which editor, if any, is hosting this build.
///
/// The question this answers is not "which platform is this": `kIsWeb` gives
/// the same reply inside an editor webview as in a browser tab. It answers
/// "is there an extension host on the other end of the bridge", which nothing
/// about the platform can tell.
///
/// The answer comes only from the marker the extension's page shim publishes
/// before `main.dart.js` runs, never from the user agent or the URL scheme,
/// both of which a browser is free to imitate. It is available synchronously
/// at startup, so nothing that depends on it has to defer: a plain browser
/// tab finds no marker and is [none] from the first frame.
///
/// Pure Dart, no Flutter imports.
enum EditorHostKind {
  /// No editor host: a native window or a plain browser tab.
  none,

  /// A VS Code extension host: the app runs in a webview owned by the
  /// EDACrux extension pack instead of in a browser tab.
  vscode,
}
