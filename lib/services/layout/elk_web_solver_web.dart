// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Browser-native elkjs solver.
///
/// Selected by the conditional import in `elk_layout_service.dart` on
/// web. Unlike the desktop path — which drives elkjs synchronously
/// inside a flutter_js QuickJS runtime on a background isolate and
/// spin-waits on the layout Promise — the browser *is* a JS engine, so
/// the same vendored `elk.bundled.js` runs natively and its
/// `elk.layout()` Promise is awaited directly via `dart:js_interop`.
/// No QuickJS, no `$wnd`/`setTimeout` GWT shims, no manual job pump.
///
/// This uses `dart:js_interop` rather than the `dart:html` the two
/// existing web files use: those wrap simple synchronous DOM getters,
/// whereas correctly awaiting a JS `Promise` requires `JSPromise.toDart`,
/// which only `dart:js_interop` provides. A `dart:html`→`package:web`
/// migration is about DOM access and does not cover this interop.
library;

import 'dart:js_interop';

import 'package:netcrux/services/layout/elk_layout_service.dart';

/// Whether the browser-native elkjs solver is available on this target.
/// `true` on web; the isolate/flutter_js path is bypassed.
const bool kElkWebSolverAvailable = true;

/// Indirect global `eval`. Called as `globalThis.eval(...)`, so the code
/// runs in global scope — the elkjs UMD bundle self-assigns
/// `window.ELK = f()`, which is all we rely on.
@JS('eval')
external JSAny? _globalEval(JSString code);

/// The string-in / string-out layout helper installed by [_bootstrapJs].
/// Takes the ELK input JSON string, resolves to the result JSON string.
@JS('__netcruxElkLayout')
external JSPromise<JSString> _elkLayoutJs(JSString inputJson);

/// Boots a singleton `ELK` and installs `__netcruxElkLayout`. Any
/// constructor failure is captured on `__netcruxElkInitError` so the Dart
/// side can surface it as a [LayoutException] instead of a bare JS throw.
///
/// Default `new ELK()` runs the layered solver in a Web Worker built from
/// an inlined blob (the bundled build needs no external worker file);
/// blob workers are permitted under the static-site CSP the viewer ships
/// with.
const String _bootstrapJs = '''
(function(){
  globalThis.__netcruxElkInitError = null;
  try {
    var __elk = new ELK();
    globalThis.__netcruxElkLayout = function(s){
      return __elk.layout(JSON.parse(s)).then(function(r){ return JSON.stringify(r); });
    };
  } catch (e) {
    globalThis.__netcruxElkInitError = String(e && e.message ? e.message : e);
  }
})();
''';

Future<void>? _initialization;

Future<void> _ensureInitialized(Future<String> Function() loadSource) {
  return _initialization ??= _initialize(loadSource);
}

Future<void> _initialize(Future<String> Function() loadSource) async {
  try {
    final source = await loadSource();
    // Define window.ELK, then construct the singleton + layout helper.
    _globalEval(source.toJS);
    _globalEval(_bootstrapJs.toJS);
    final err = _globalEval('globalThis.__netcruxElkInitError || ""'.toJS);
    final errStr = (err as JSString?)?.toDart ?? '';
    if (errStr.isNotEmpty) {
      throw LayoutException('elkjs constructor threw: $errStr');
    }
  } on LayoutException {
    _initialization = null;
    rethrow;
  } on Object catch (e) {
    _initialization = null;
    throw LayoutException(
      'Failed to initialize the browser elkjs runtime',
      cause: e,
    );
  }
}

/// Solves [inputJson] with browser-native elkjs and returns the layout
/// result JSON string. Throws [LayoutException] on init failure, an elk
/// rejection, or an empty result — matching the desktop solver's error
/// contract so `currentLaidOutGraph` handles both platforms identically.
Future<String> solveElkOnWeb(
  String inputJson,
  Future<String> Function() loadSource,
) async {
  await _ensureInitialized(loadSource);
  try {
    final result = await _elkLayoutJs(inputJson.toJS).toDart;
    final resultStr = result.toDart;
    if (resultStr.isEmpty) {
      throw const LayoutException('elkjs returned an empty layout');
    }
    return resultStr;
  } on LayoutException {
    rethrow;
  } on Object catch (e) {
    throw LayoutException('elkjs rejected the layout input: $e', cause: e);
  }
}
