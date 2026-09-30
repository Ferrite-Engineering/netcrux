// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:netcrux/services/web/web_json_loader.dart';

/// Non-web implementation of [fetchWebJson].
///
/// Accepts `file://` URLs and local-path strings and reads the file
/// from disk. Used in unit tests that exercise the loader's behavior
/// without running in a browser, and as the fallback when web-only
/// builds slip into a VM context (it would be a bug for production
/// code to hit this on web — the conditional import in
/// `web_json_loader.dart` routes web builds to
/// `web_json_loader_web.dart` instead).
Future<String> fetchPlatformJson(String url) async {
  final path = _toLocalPath(url);
  final file = File(path);
  if (!file.existsSync()) {
    throw WebJsonLoadException(
      'JSON file not found at $path',
    );
  }
  try {
    return await file.readAsString();
  } on FileSystemException catch (e) {
    throw WebJsonLoadException(
      'Failed to read JSON at $path',
      cause: e,
    );
  }
}

/// Normalizes [url] to a local filesystem path. Supports `file://`
/// URIs and bare relative / absolute paths.
String _toLocalPath(String url) {
  if (url.startsWith('file://')) {
    return Uri.parse(url).toFilePath();
  }
  return url;
}
