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
/// It is the only browser engine. When the worker script or the module
/// cannot load (a file missing from the deployment, or a browser that
/// refuses module workers or WebAssembly), the solve fails with a
/// [LayoutFailureKind.engineUnavailable] [LayoutException] whose
/// [LayoutException.engineFile] names the file, and the next solve tries
/// again with a fresh worker. An input the engine rejects is a plain
/// [LayoutException], as it is on desktop.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:meta/meta.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart'
    show kEditorHostLayoutWorkerGlobal;
import 'package:netcrux/services/layout/elk_layout_service.dart';

/// Whether the browser solver is available on this target. `true` on web;
/// the isolate path is bypassed.
const bool kElkWebSolverAvailable = true;

/// The worker script, relative to the page's base URL. `flutter build web`
/// copies `web/wasm/` into the bundle beside `index.html`.
const String kElkWasmWorkerPath = 'wasm/elk_wasm_worker.js';

/// The module the worker loads when it does not say which file failed.
const String _kElkWasmModuleFile = 'elk_wasm_bg.wasm';

/// How long the worker may take to load the module before the solver treats
/// the load as failed.
const Duration kElkWasmLoadTimeout = Duration(seconds: 30);

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
  external String? get file;
  external bool? get fatal;
  external String? get phase;
  external double? get fraction;
}

extension type _Request._(JSObject _) implements JSObject {
  external factory _Request({int id, String input});
}

/// The URL of a worker an editor host's page shim staged, or null.
///
/// An editor webview serves its files from a different origin than its
/// document, and a browser refuses to start a worker from another origin. The
/// shim therefore fetches the worker's files and starts it from a blob URL,
/// published here. Unset in a browser tab, where the worker's relative path
/// resolves normally.
@JS(kEditorHostLayoutWorkerGlobal)
external JSString? get _hostLayoutWorkerUrl;

/// The worker script to start: the host's staged blob when there is one and
/// the solver has not been pointed elsewhere, otherwise [_workerUrl].
String _resolveWorkerUrl() {
  if (_workerUrl != kElkWasmWorkerPath) return _workerUrl;
  try {
    final hosted = _hostLayoutWorkerUrl?.toDart;
    if (hosted != null && hosted.isNotEmpty) return hosted;
  } on Object {
    // A global another script wrote that is not a string: use the default.
  }
  return _workerUrl;
}

@JS('console.warn')
external void _consoleWarn(JSString message);

// ── State ───────────────────────────────────────────────────────────────────

String _workerUrl = kElkWasmWorkerPath;
Duration _loadTimeout = kElkWasmLoadTimeout;
void Function(String message) _log = _warn;

void _warn(String message) => _consoleWarn(message.toJS);

/// The live worker, or null when none is running (before the first solve,
/// after a cancel, a trap or a load failure). The next solve starts one.
_Worker? _worker;
Future<void>? _workerReady;

int _nextId = 0;
final Map<int, Completer<String>> _pending = <int, Completer<String>>{};

/// The progress listeners of the solves in [_pending], by id.
final Map<int, void Function(LayoutProgress progress)> _listeners =
    <int, void Function(LayoutProgress progress)>{};

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

/// Drops the worker, so the next solve starts from nothing.
@visibleForTesting
void debugResetElkWebSolver() {
  _discardWorker(const LayoutException('layout engine reset'));
}

/// Whether a solve is running in the worker right now.
bool get elkWebLayoutInFlight => _pending.isNotEmpty;

/// Abandons every solve in flight: each pending [solveElkOnWeb] completes
/// with a [LayoutException] and the worker is terminated, which stops the
/// solve, since the engine cannot be interrupted from outside. The next solve
/// starts a fresh worker. A no-op when nothing is in flight, so the warm
/// worker survives ordinary navigation.
void cancelElkOnWeb() {
  if (_pending.isEmpty) return;
  _discardWorker(const LayoutCancelledException());
}

/// Solves [inputJson] and returns the laid-out ELK JSON, passing the
/// engine's progress reports to [onProgress] as the worker posts them.
/// Throws [LayoutCancelledException] when [cancelElkOnWeb] abandons it,
/// a [LayoutFailureKind.engineUnavailable] [LayoutException] naming the file
/// when the worker script or the module cannot load, and a [LayoutException]
/// when the engine rejects the input. There is no time limit: the user can
/// stop the solve, and cancelling terminates the worker.
Future<String> solveElkOnWeb(
  String inputJson, {
  void Function(LayoutProgress progress)? onProgress,
}) async {
  try {
    await _ensureWorker();
  } on LayoutException catch (e) {
    if (e.kind == LayoutFailureKind.engineUnavailable) {
      _log(
        'netcrux: layout engine: ${e.engineFile} did not load '
        '(${e.message})',
      );
    }
    rethrow;
  }
  final id = _nextId++;
  final completer = _pending[id] = Completer<String>();
  if (onProgress != null) _listeners[id] = onProgress;
  _worker!.postMessage(_Request(id: id, input: inputJson));
  return await completer.future;
}

/// The failure for an engine file that did not load: [file] beside the
/// worker script (`wasm/` in a deployed bundle) unless it is already a path
/// or URL.
LayoutException _unavailable(String file, String reason) {
  final String named;
  if (file.contains('/') || file.contains(':')) {
    named = file;
  } else {
    final slash = _workerUrl.lastIndexOf('/');
    named = slash < 0 ? file : '${_workerUrl.substring(0, slash + 1)}$file';
  }
  return LayoutException(
    'the layout engine file $named did not load: $reason',
    kind: LayoutFailureKind.engineUnavailable,
    engineFile: named,
  );
}

Future<void> _ensureWorker() => _workerReady ??= _startWorker();

Future<void> _startWorker() {
  final ready = Completer<void>();
  final url = _resolveWorkerUrl();
  final _Worker worker;
  try {
    worker = _Worker(url.toJS, _WorkerOptions(type: 'module'));
  } on Object catch (e) {
    _workerReady = null;
    return Future<void>.error(
      _unavailable(_workerUrl, 'could not start the layout worker: $e'),
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
    final LayoutException failure;
    if (ready.isCompleted) {
      // A running worker's own error, not a load failure.
      failure = LayoutException(
        'layout worker error: ${message ?? 'unknown error'}',
      );
    } else {
      // Before `ready`, an error event means the script itself did not load
      // (a module worker raises a plain `Event` with no message for a
      // missing file) or threw while loading.
      failure = _unavailable(
        _workerUrl,
        message != null && message.isNotEmpty
            ? message
            : 'the worker script failed to load',
      );
      ready.completeError(failure);
    }
    _discardWorker(failure);
  }).toJS;
  return ready.future.timeout(
    _loadTimeout,
    onTimeout: () {
      final failure = _unavailable(
        _kElkWasmModuleFile,
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
      final file = reply.file;
      final failure = _unavailable(
        file == null || file.isEmpty ? _kElkWasmModuleFile : file,
        reply.message ?? 'unknown error',
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
