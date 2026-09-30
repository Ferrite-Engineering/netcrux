// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Parsed shape of the query string + URL fragment NetCrux's web build
/// honors on first load.
///
/// The contract:
///
///   - `?json=<encoded-url>` — auto-load a remote pre-elaborated Yosys
///     JSON document. The loader does not enforce a scheme, but a page
///     served over HTTPS (as `app.netcrux.app` is) can only fetch HTTPS,
///     and the server must allow the viewer's origin.
///   - `#scope=top.cpu.alu` — auto-push into a named hierarchical
///     scope after the netlist loads. The dot-delimited path matches
///     the canonical hierarchical-path helper used by the cross-probe
///     layer.
///   - `#sig=<identifier>` — auto-select a named signal. Both can be
///     present; `#scope=` is applied first, then `#sig=` if present.
///
/// Web-only — the desktop entry point ignores [WebLaunchParams] entirely
/// because it uses the CLI argument parser instead.
@immutable
class WebLaunchParams {
  /// Creates a parsed [WebLaunchParams].
  const WebLaunchParams({
    this.jsonUrl,
    this.autoScope,
    this.autoSignal,
  });

  /// Parses [queryString] (without the leading `?`) and [fragment]
  /// (without the leading `#`).
  ///
  /// Both [queryString] and [fragment] may be empty; an empty pair
  /// yields [WebLaunchParams.empty]. Unknown keys are silently
  /// ignored for forward-compatibility.
  ///
  /// Fragment syntax supports key=value pairs separated by `&`,
  /// matching browser URL conventions (`#scope=foo&sig=bar`) as well
  /// as the single-key shorthand (`#scope=foo`).
  factory WebLaunchParams.parse({
    String queryString = '',
    String fragment = '',
  }) {
    String? jsonUrl;
    String? autoScope;
    String? autoSignal;

    if (queryString.isNotEmpty) {
      final params = Uri.splitQueryString(queryString);
      final raw = params['json'];
      if (raw != null && raw.isNotEmpty) {
        jsonUrl = raw;
      }
    }

    if (fragment.isNotEmpty) {
      final params = Uri.splitQueryString(fragment);
      final scope = params['scope'];
      if (scope != null && scope.isNotEmpty) {
        autoScope = scope;
      }
      final sig = params['sig'];
      if (sig != null && sig.isNotEmpty) {
        autoSignal = sig;
      }
    }

    if (jsonUrl == null && autoScope == null && autoSignal == null) {
      return WebLaunchParams.empty;
    }
    return WebLaunchParams(
      jsonUrl: jsonUrl,
      autoScope: autoScope,
      autoSignal: autoSignal,
    );
  }

  /// Empty instance — no `?json`, no `#scope`, no `#sig` were present.
  /// The web viewer then shows its start screen, whose one action opens a
  /// netlist JSON file.
  static const WebLaunchParams empty = WebLaunchParams();

  /// Value of the `json` query parameter. `null` when absent or empty.
  /// The workspace opens it as the netlist of a new tab; the pipeline
  /// fetches it through `PrebuiltNetlistLoader`, which tests override to
  /// feed a document without the network.
  final String? jsonUrl;

  /// Value of the `scope` URL fragment field (`#scope=top.cpu.alu`).
  /// Applied after the netlist loads — pushes the hierarchy tree into
  /// the named scope (see `WebDeepLink`).
  final String? autoScope;

  /// Value of the `sig` URL fragment field (`#sig=<name>`). Applied
  /// after `#scope=` if both are present.
  final String? autoSignal;

  /// Returns true when this instance carries no actionable hints.
  bool get isEmpty =>
      jsonUrl == null && autoScope == null && autoSignal == null;

  @override
  bool operator ==(Object other) =>
      other is WebLaunchParams &&
      other.jsonUrl == jsonUrl &&
      other.autoScope == autoScope &&
      other.autoSignal == autoSignal;

  @override
  int get hashCode => Object.hash(jsonUrl, autoScope, autoSignal);

  @override
  String toString() =>
      'WebLaunchParams(json=$jsonUrl, scope=$autoScope, sig=$autoSignal)';
}
