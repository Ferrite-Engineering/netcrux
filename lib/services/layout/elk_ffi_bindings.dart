// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Hand-written `dart:ffi` binding for the C ABI of `native/elk_ffi` (see
// its `src/lib.rs`). Small enough that a generator would be more to maintain
// than the binding.

import 'dart:convert';
import 'dart:ffi' as ffi;

typedef _AllocDart = ffi.Pointer<ffi.Uint8> Function(int len);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Uint8> ptr, int len);
typedef _LayoutDart =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Uint8> ptr,
      int len,
      ffi.Pointer<ffi.Size> outLen,
      ffi.Pointer<ffi.Int32> status,
    );
typedef _VersionDart = ffi.Pointer<ffi.Uint8> Function();
typedef _JobStartDart =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Uint8> ptr,
      int len,
    );
typedef _JobPollDart =
    int Function(
      ffi.Pointer<ffi.Void> job,
      ffi.Pointer<ffi.Int32> phase,
      ffi.Pointer<ffi.Double> fraction,
    );
typedef _JobCancelDart = void Function(ffi.Pointer<ffi.Void> job);
typedef _JobFinishDart =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Void> job,
      ffi.Pointer<ffi.Size> outLen,
      ffi.Pointer<ffi.Int32> status,
    );

/// `elk_job_finish` status: the buffer is the laid-out document.
const int _statusOk = 0;

/// `elk_job_finish` status: the job was cancelled.
const int _statusCancelled = 2;

/// The outcome of one native solve: the laid-out ELK JSON document, the
/// engine's error message, or a cancel.
class ElkFfiResult {
  const ElkFfiResult._(this.json, this.error, {this.cancelled = false});

  /// The laid-out document, or `null` when the solve failed or was
  /// cancelled.
  final String? json;

  /// The engine's message when the solve failed or was cancelled, else
  /// `null`.
  final String? error;

  /// Whether the solve stopped because it was cancelled.
  final bool cancelled;
}

/// The latest progress of a running [ElkFfiJob]: the elkrs phase code (1
/// cycle breaking, 2 layering, 3 crossing minimization, 4 node placement,
/// 5 edge routing, 0 none yet) and the share of the layout done, `null` when
/// the engine does not know it.
typedef ElkFfiProgress = ({int phase, double? fraction});

/// One layout running on the engine's own thread, started by
/// [ElkFfiBindings.startJob]. The calling isolate stays free: it polls
/// [poll], may [cancel], and must end every job with [finish], which
/// releases it.
class ElkFfiJob {
  ElkFfiJob._(this._bindings, this._job);

  final ElkFfiBindings _bindings;
  ffi.Pointer<ffi.Void> _job;

  /// Whether [finish] has released the job.
  bool get isFinished => _job == ffi.nullptr;

  /// Whether the job has its result, with its latest progress.
  ({bool done, ElkFfiProgress progress}) poll() {
    if (isFinished) throw StateError('elk_ffi job already finished');
    final phase = _bindings._alloc(ffi.sizeOf<ffi.Int32>()).cast<ffi.Int32>();
    final fraction = _bindings
        ._alloc(ffi.sizeOf<ffi.Double>())
        .cast<ffi.Double>();
    try {
      final done = _bindings._jobPoll(_job, phase, fraction) != 0;
      final value = fraction.value;
      return (
        done: done,
        progress: (phase: phase.value, fraction: value.isNaN ? null : value),
      );
    } finally {
      _bindings._free(fraction.cast<ffi.Uint8>(), ffi.sizeOf<ffi.Double>());
      _bindings._free(phase.cast<ffi.Uint8>(), ffi.sizeOf<ffi.Int32>());
    }
  }

  /// Asks the engine to stop; it does so within a pipeline step, and
  /// [finish] then reports the cancel. A no-op once finished.
  void cancel() {
    if (!isFinished) _bindings._jobCancel(_job);
  }

  /// Waits for the result (at once, after [poll] reported it done) and
  /// releases the job.
  ElkFfiResult finish() {
    if (isFinished) throw StateError('elk_ffi job already finished');
    final job = _job;
    _job = ffi.nullptr;
    return _bindings._collect(
      (outLen, status) => _bindings._jobFinish(job, outLen, status),
    );
  }
}

/// Bound entry points of one opened `elk_ffi` library.
class ElkFfiBindings {
  /// Looks up every symbol at once, so a library that is the wrong build
  /// fails here, with the symbol's name, rather than on the first solve.
  ElkFfiBindings(ffi.DynamicLibrary library)
    : _alloc = library
          .lookupFunction<
            ffi.Pointer<ffi.Uint8> Function(ffi.Size),
            _AllocDart
          >(
            'elk_alloc',
          ),
      _free = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size),
            _FreeDart
          >('elk_free'),
      _layout = library
          .lookupFunction<
            ffi.Pointer<ffi.Uint8> Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Size,
              ffi.Pointer<ffi.Size>,
              ffi.Pointer<ffi.Int32>,
            ),
            _LayoutDart
          >('elk_layout_json'),
      _version = library
          .lookupFunction<ffi.Pointer<ffi.Uint8> Function(), _VersionDart>(
            'elk_engine_version',
          ),
      _jobStart = library
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>, ffi.Size),
            _JobStartDart
          >('elk_job_start'),
      _jobPoll = library
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Int32>,
              ffi.Pointer<ffi.Double>,
            ),
            _JobPollDart
          >('elk_job_poll'),
      _jobCancel = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            _JobCancelDart
          >('elk_job_cancel'),
      _jobFinish = library
          .lookupFunction<
            ffi.Pointer<ffi.Uint8> Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Size>,
              ffi.Pointer<ffi.Int32>,
            ),
            _JobFinishDart
          >('elk_job_finish');

  final _AllocDart _alloc;
  final _FreeDart _free;
  final _LayoutDart _layout;
  final _VersionDart _version;
  final _JobStartDart _jobStart;
  final _JobPollDart _jobPoll;
  final _JobCancelDart _jobCancel;
  final _JobFinishDart _jobFinish;

  /// The engine's self-description, e.g. `elkrs 0.1.1`.
  String engineVersion() {
    final ptr = _version();
    var len = 0;
    while (ptr[len] != 0) {
      len++;
    }
    return utf8.decode(ptr.asTypedList(len));
  }

  /// Lays out [inputJson] on the engine's own thread and returns the result
  /// once it is done. Blocks the calling isolate for the whole solve, which
  /// is why the layout service calls it from its worker isolate.
  ElkFfiResult layoutJson(String inputJson) {
    return _withInput(
      inputJson,
      (input, len) => _collect(
        (outLen, status) => _layout(input, len, outLen, status),
      ),
    );
  }

  /// Starts laying out [inputJson] on the engine's own thread and returns
  /// at once; the caller polls the job, may cancel it, and finishes it.
  ElkFfiJob startJob(String inputJson) {
    // The engine copies the input, so the buffer is released straight away.
    final job = _withInput(inputJson, _jobStart);
    return ElkFfiJob._(this, job);
  }

  /// Copies [text] into an engine buffer for the length of [use].
  T _withInput<T>(
    String text,
    T Function(ffi.Pointer<ffi.Uint8> input, int len) use,
  ) {
    final bytes = utf8.encode(text);
    final input = _alloc(bytes.length);
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      return use(input, bytes.length);
    } finally {
      _free(input, bytes.length);
    }
  }

  /// Calls [produce] with the out-parameters an outcome buffer needs, then
  /// decodes and releases the buffer it returns.
  ElkFfiResult _collect(
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Size> outLen,
      ffi.Pointer<ffi.Int32> status,
    )
    produce,
  ) {
    final outLen = _alloc(ffi.sizeOf<ffi.Size>()).cast<ffi.Size>();
    final status = _alloc(ffi.sizeOf<ffi.Int32>()).cast<ffi.Int32>();
    ffi.Pointer<ffi.Uint8> output = ffi.nullptr;
    var outputLength = 0;
    try {
      output = produce(outLen, status);
      outputLength = outLen.value;
      final text = utf8.decode(output.asTypedList(outputLength));
      return switch (status.value) {
        _statusOk => ElkFfiResult._(text, null),
        _statusCancelled => ElkFfiResult._(null, text, cancelled: true),
        _ => ElkFfiResult._(null, text),
      };
    } finally {
      if (output != ffi.nullptr) _free(output, outputLength);
      _free(status.cast<ffi.Uint8>(), ffi.sizeOf<ffi.Int32>());
      _free(outLen.cast<ffi.Uint8>(), ffi.sizeOf<ffi.Size>());
    }
  }
}
