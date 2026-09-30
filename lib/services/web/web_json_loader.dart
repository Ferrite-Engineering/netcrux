// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/web/web_json_loader_stub.dart'
    if (dart.library.html) 'package:netcrux/services/web/web_json_loader_web.dart';

/// Fetches a pre-elaborated Yosys JSON document.
///
/// On web (when `dart.library.html` is available), [fetchWebJson] is
/// implemented via the browser's `HttpRequest` API. On VM / desktop
/// hosts it falls back to `File.readAsString`, accepting `file://`
/// URLs and bare paths — exists so unit tests can exercise the loader
/// without spinning up a browser.
///
/// Network or filesystem errors surface as [WebJsonLoadException].
/// Callers feed the returned raw JSON through `YosysJsonParser` /
/// `StreamingYosysJsonReader` to produce a `NetlistModel`.
Future<String> fetchWebJson(String url) => fetchPlatformJson(url);

/// Thrown by [fetchWebJson] on transport, parse, or read failure.
/// Carries a one-line user-facing message and the underlying cause so
/// the diagnostics drawer can surface details.
class WebJsonLoadException implements Exception {
  /// Creates a load exception.
  const WebJsonLoadException(this.message, {this.cause});

  /// Short user-actionable message.
  final String message;

  /// Underlying error — null when the failure is structural.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'WebJsonLoadException: $message'
      : 'WebJsonLoadException: $message ($cause)';
}
