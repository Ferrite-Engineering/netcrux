// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// This file is only ever compiled on web — selected via the
// conditional import in `window_location.dart`. `dart:html` is the
// historical web API; migration to `package:web` + `dart:js_interop`
// is tracked alongside the broader Phase-N migration sweep.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:netcrux/core/web/web_launch_params.dart';

/// Web implementation: reads `window.location.search` (without the
/// leading `?`) and `window.location.hash` (without the leading `#`)
/// and parses them into a [WebLaunchParams].
///
/// Used by `bootstrap()` on web only; the conditional import in
/// `window_location.dart` routes the desktop / VM cases to the stub
/// instead.
WebLaunchParams readWebLaunchParams() {
  final search = html.window.location.search ?? '';
  final hash = html.window.location.hash;
  // `search` keeps its leading `?`; strip it for Uri.splitQueryString.
  final queryString = search.startsWith('?') ? search.substring(1) : search;
  // `hash` includes the leading `#`; strip it for splitQueryString.
  final fragment = hash.startsWith('#') ? hash.substring(1) : hash;
  return WebLaunchParams.parse(
    queryString: queryString,
    fragment: fragment,
  );
}
