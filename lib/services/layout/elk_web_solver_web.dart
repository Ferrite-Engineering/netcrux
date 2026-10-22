// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The browser's layout engine.
///
/// Selected by the conditional import in `elk_layout_service.dart` on web.
/// The solve runs in the vendored elkrs port compiled to WebAssembly
/// (`native/elk_wasm`), the engine the desktop build runs natively, inside a
/// dedicated module Web Worker (`web/wasm/elk_wasm_worker.js`), so a
/// multi-second scope never blocks the page and cancelling a solve is
/// terminating the worker. The page posts the ELK input JSON and awaits the
/// laid-out JSON; the wasm call is string in, string out, the same contract
/// as `native/elk_ffi`, and produces the same bytes.
///
/// When the module cannot load (the worker script or the `.wasm` is missing,
/// or the browser refuses module workers or WebAssembly), the solver says so
/// on the console once and falls back to the vendored elkjs, evaluated on the
/// page and awaited through its own Promise, which is what the web viewer
/// ran before. A load failure is the only fallback: an input the wasm engine
/// rejects is a [LayoutException], as it is on desktop.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:meta/meta.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';

/// Whether the browser solver is available on this target. `true` on web;
/// the isolate path is bypassed.
const bool kElkWebSolverAvailable = true;

/// The worker script, relative to the page's base URL. `flutter build web`
/// copies `web/wasm/` into the bundle beside `index.html`.
const String kElkWasmWorkerPath = 'wasm/elk_wasm_worker.js';

/// How long the worker may take to load the module before the solver treats
/// the load as failed and falls back to elkjs.
const Duration kElkWasmLoadTimeout = Duration(seconds: 30);

/// Which engine the browser solver is using.
enum ElkWebEngine {
  /// The elkrs port as WebAssembly in a Web Worker.
  wasm,

  /// The vendored elkjs on the page, after the wasm module failed to load.
  elkjs,
}

// ── JS interop ──────────────────────────────────────────────────────────────

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(JSString url, _WorkerOptions options);
  external void postMessage(JSAny? message);
  external void terminate();
  external JSFunction? get onmessage;
  external set onmessage(JSFunction? handler);
  external JSFunction? get onerror;
  external set onerror(JSFunction? handler);
}

extension type _WorkerOptions._(JSObject _) implements JSObject {
  external factory _WorkerOptions({String type});
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
}

extension type _ErrorEvent._(JSObject _) implements JSObject {
  /// Absent on the plain `Event` a module worker raises when its script
  /// fails to load.
  external String? get message;
  external void preventDefault();
}

extension type _Reply._(JSObject _) implements JSObject {
  external String get type;
  external int? get id;
  external String? get json;
  external String? get message;
  external bool? get fatal;
  external String? get phase;
  external double? get fraction;
}

extension type _Request._(JSObject _) implements JSObject {
  external factory _Request({int id, String input});
}

@JS('console.warn')
external void _consoleWarn(JSString message);

/// Indirect global `eval`, for the elkjs fallback. Called as
/// `globalThis.eval(...)`, so the code runs in global scope: the elkjs UMD
/// bundle self-assigns `window.ELK = f()`, which is all the fallback needs.
@JS('eval')
external JSAny? _globalEval(JSString code);

/// The string-in / string-out helper [_elkjsBootstrap] installs.
@JS('__netcruxElkLayout')
external JSPromise<JSString> _elkjsLayout(JSString inputJson);

/// Boots a singleton `ELK` and installs `__netcruxElkLayout`. A constructor
/// failure is captured on `__netcruxElkInitError` so the Dart side can raise
/// a [LayoutException] instead of a bare JS throw.
const String _elkjsBootstrap = '''
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

// ── State ───────────────────────────────────────────────────────────────────

String _workerUrl = kElkWasmWorkerPath;
Duration _loadTimeout = kElkWasmLoadTimeout;
void Function(String message) _log = _warn;

void _warn(String message) => _consoleWarn(message.toJS);

/// The engine chosen by the first solve; null until then.
Future<ElkWebEngine>? _engine;

/// The live worker, or null when none is running (before the first solve,
/// after a cancel or a trap). The next wasm solve starts one.
_Worker? _worker;
Future<void>? _workerReady;

int _nextId = 0;
final Map<int, Completer<String>> _pending = <int, Completer<String>>{};

/// The progress listeners of the solves in [_pending], by id.
final Map<int, void Function(LayoutProgress progress)> _listeners =
    <int, void Function(LayoutProgress progress)>{};

Future<void>? _elkjsInitialization;

/// The engine the solver settled on, or null before the first solve.
@visibleForTesting
Future<ElkWebEngine>? get debugElkWebEngine => _engine;

/// Points the solver at another worker script (a test serves it from its
/// own directory), another load timeout, or another log sink. Resets the
/// solver's state.
@visibleForTesting
void debugConfigureElkWebSolver({
  String? workerUrl,
  Duration? loadTimeout,
  void Function(String message)? log,
}) {
  debugResetElkWebSolver();
  _workerUrl = workerUrl ?? kElkWasmWorkerPath;
  _loadTimeout = loadTimeout ?? kElkWasmLoadTimeout;
  _log = log ?? _warn;
}

/// Drops the worker, the engine choice and the elkjs runtime, so the next
/// solve starts from nothing.
@visibleForTesting
void debugResetElkWebSolver() {
  _discardWorker(const LayoutException('layout engine reset'));
  _engine = null;
  _elkjsInitialization = null;
}

/// Whether a solve is running in the worker right now.
bool get elkWebLayoutInFlight => _pending.isNotEmpty;

/// Abandons every solve in flight: each pending [solveElkOnWeb] completes
/// with a [LayoutException] and the worker is terminated, which stops the
/// solve, since the engine cannot be interrupted from outside. The next solve
/// starts a fresh worker. A no-op when nothing is in flight, so the warm
/// worker survives ordinary navigation. The elkjs fallback runs on the page
/// and is not tracked here; its solves run to completion, as they did before
/// the wasm engine.
void cancelElkOnWeb() {
  if (_pending.isEmpty) return;
  _discardWorker(const LayoutCancelledException());
}

/// Solves [inputJson] and returns the laid-out ELK JSON, passing the wasm
/// engine's progress reports to [onProgress] as the worker posts them (elkjs
/// reports none). Throws [LayoutCancelledException] when [cancelElkOnWeb]
/// abandons it, and [LayoutException] when the engine rejects the input or
/// nothing can start. There is no time limit: the user can stop the solve,
/// and cancelling terminates the worker. [loadSource] reads the vendored
/// elkjs, and is called only when the wasm module cannot load.
Future<String> solveElkOnWeb(
  String inputJson,
  Future<String> Function() loadSource, {
  void Function(LayoutProgress progress)? onProgress,
}) async {
  final engine = await (_engine ??= _chooseEngine());
  return switch (engine) {
    ElkWebEngine.wasm => await _solveInWorker(inputJson, onProgress),
    ElkWebEngine.elkjs => await _solveWithElkjs(inputJson, loadSource),
  };
}

/// Starts the worker once. If the module loads, every solve uses it; if not,
/// the reason is logged and every solve this session uses elkjs.
Future<ElkWebEngine> _chooseEngine() async {
  try {
    await _ensureWorker();
    return ElkWebEngine.wasm;
  } on LayoutException catch (e) {
    _log(
      'netcrux: layout engine: the WebAssembly engine did not load '
      '(${e.message}); falling back to elkjs',
    );
    return ElkWebEngine.elkjs;
  }
}

Future<void> _ensureWorker() => _workerReady ??= _startWorker();

Future<void> _startWorker() {
  final ready = Completer<void>();
  final _Worker worker;
  try {
    worker = _Worker(_workerUrl.toJS, _WorkerOptions(type: 'module'));
  } on Object catch (e) {
    _workerReady = null;
    return Future<void>.error(
      LayoutException('could not start the layout worker: $e', cause: e),
    );
  }
  _worker = worker;
  worker.onmessage = ((_MessageEvent event) {
    final reply = event.data as _Reply?;
    if (reply == null || !identical(_worker, worker)) return;
    _onReply(reply, ready);
  }).toJS;
  worker.onerror = ((_ErrorEvent event) {
    event.preventDefault();
    if (!identical(_worker, worker)) return;
    final message = event.message;
    final reason = message != null && message.isNotEmpty
        ? message
        : 'the worker script $_workerUrl failed to load';
    final failure = LayoutException('layout worker error: $reason');
    if (!ready.isCompleted) ready.completeError(failure);
    _discardWorker(failure);
  }).toJS;
  return ready.future.timeout(
    _loadTimeout,
    onTimeout: () {
      final failure = LayoutException(
        'the layout worker did not load within ${_loadTimeout.inSeconds} s',
      );
      if (identical(_worker, worker)) _discardWorker(failure);
      throw failure;
    },
  );
}

void _onReply(_Reply reply, Completer<void> ready) {
  switch (reply.type) {
    case 'ready':
      if (!ready.isCompleted) ready.complete();
    case 'load-error':
      final failure = LayoutException(
        'the WebAssembly module failed to load: ${reply.message}',
      );
      if (!ready.isCompleted) ready.completeError(failure);
      _discardWorker(failure);
    case 'progress':
      final phase = LayoutPhase.fromName(reply.phase ?? '');
      final fraction = reply.fraction;
      if (phase != null) {
        _listeners[reply.id]?.call(
          LayoutProgress(
            phase: phase,
            fraction: fraction == null || fraction.isNaN ? null : fraction,
          ),
        );
      }
    case 'result':
      _listeners.remove(reply.id);
      final completer = _pending.remove(reply.id);
      final json = reply.json ?? '';
      if (json.isEmpty) {
        completer?.completeError(
          const LayoutException('the layout engine returned an empty layout'),
        );
      } else {
        completer?.complete(json);
      }
    case 'error':
      final failure = LayoutException(
        'the layout engine rejected the input: ${reply.message}',
      );
      if (reply.fatal ?? false) {
        // A trapped module is not reusable: fail everything queued on it.
        _discardWorker(failure);
      } else {
        _listeners.remove(reply.id);
        _pending.remove(reply.id)?.completeError(failure);
      }
  }
}

/// Terminates the worker and fails every pending solve with [failure].
void _discardWorker(LayoutException failure) {
  _worker?.terminate();
  _worker = null;
  _workerReady = null;
  final pending = List<Completer<String>>.of(_pending.values);
  _pending.clear();
  _listeners.clear();
  for (final completer in pending) {
    if (!completer.isCompleted) completer.completeError(failure);
  }
}

Future<String> _solveInWorker(
  String inputJson,
  void Function(LayoutProgress progress)? onProgress,
) async {
  await _ensureWorker();
  final id = _nextId++;
  final completer = _pending[id] = Completer<String>();
  if (onProgress != null) _listeners[id] = onProgress;
  _worker!.postMessage(_Request(id: id, input: inputJson));
  return await completer.future;
}

// ── elkjs fallback ──────────────────────────────────────────────────────────

Future<String> _solveWithElkjs(
  String inputJson,
  Future<String> Function() loadSource,
) async {
  await (_elkjsInitialization ??= _initializeElkjs(loadSource));
  try {
    final result = (await _elkjsLayout(inputJson.toJS).toDart).toDart;
    if (result.isEmpty) {
      throw const LayoutException('elkjs returned an empty layout');
    }
    return result;
  } on LayoutException {
    rethrow;
  } on Object catch (e) {
    throw LayoutException('elkjs rejected the layout input: $e', cause: e);
  }
}

Future<void> _initializeElkjs(Future<String> Function() loadSource) async {
  try {
    _globalEval((await loadSource()).toJS);
    _globalEval(_elkjsBootstrap.toJS);
    final err = _globalEval('globalThis.__netcruxElkInitError || ""'.toJS);
    final errStr = (err as JSString?)?.toDart ?? '';
    if (errStr.isNotEmpty) {
      throw LayoutException('elkjs constructor threw: $errStr');
    }
  } on LayoutException {
    _elkjsInitialization = null;
    rethrow;
  } on Object catch (e) {
    _elkjsInitialization = null;
    throw LayoutException(
      'Failed to initialize the browser elkjs runtime',
      cause: e,
    );
  }
}
