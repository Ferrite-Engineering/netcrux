// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// This file is only ever compiled on web — it's selected via the
// conditional import in `web_json_loader.dart`. Suppressing the
// avoid_web_libraries_in_flutter lint is intentional: this file is
// gated to web by construction.
// We continue to use `dart:html` directly rather than the newer
// `package:web` + `dart:js_interop` because the only API we need
// (`HttpRequest.getString`) is one line and well-supported, so it moves
// to package:web together with the app's other `dart:html` uses.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'package:netcrux/services/web/web_json_loader.dart';

/// Web implementation of [fetchWebJson].
///
/// Fetches the JSON document at [url] via the browser's `HttpRequest`
/// API. CORS / network failures surface as [WebJsonLoadException]
/// with the underlying browser error attached as the cause.
Future<String> fetchPlatformJson(String url) async {
  try {
    final body = await html.HttpRequest.getString(url);
    if (body.isEmpty) {
      throw const WebJsonLoadException(
        'Remote JSON document was empty',
      );
    }
    return body;
  } on html.ProgressEvent catch (e) {
    throw WebJsonLoadException(
      'Failed to fetch $url',
      cause: e.toString(),
    );
  } on Exception catch (e) {
    throw WebJsonLoadException(
      'Failed to fetch $url',
      cause: e,
    );
  }
}
