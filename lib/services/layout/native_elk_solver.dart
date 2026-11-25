// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/layout/elk_ffi_bindings.dart';
import 'package:netcrux/services/layout/elk_ffi_library_io.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';

/// The desktop layout engine: the vendored elkrs port of the Eclipse Layout
/// Kernel, called through `native/elk_ffi`'s C ABI.
///
/// ELK JSON in and laid-out ELK JSON out, matching the stored ELK references
/// for NetCrux's inputs (the parity test holds it to that), at native speed
/// and memory. A solve can also run as a job ([start]) that reports its
/// progress and stops on request. It is the only desktop engine: there is no
/// JavaScript engine to fall back to.
class NativeElkSolver implements ElkJobSolver {
  NativeElkSolver._(this._bindings, this.engineDescription);

  /// Opens the bundled library and binds its entry points.
  ///
  /// Throws a [LayoutException] of kind
  /// [LayoutFailureKind.engineUnavailable] whose [LayoutException.engineFile]
  /// is the library's file name (`libelk_ffi.dylib`, `libelk_ffi.so` or
  /// `elk_ffi.dll`) when the library cannot be found, cannot be loaded or is
  /// the wrong build. [opener] is the test seam over `dlopen`.
  factory NativeElkSolver.open({ElkFfiLibraryOpener? opener}) {
    // The bare library name until the platform's file name is known (a
    // platform with no native build throws before it is).
    var file = 'elk_ffi';
    try {
      file = elkFfiLibraryFileName();
      final library = opener == null
          ? openElkFfiLibrary()
          : openElkFfiLibrary(opener: opener);
      final bindings = ElkFfiBindings(library);
      return NativeElkSolver._(
        bindings,
        'native (${bindings.engineVersion()})',
      );
    } on Object catch (e) {
      throw LayoutException(
        'the layout engine library $file could not be loaded: $e',
        cause: e,
        kind: LayoutFailureKind.engineUnavailable,
        engineFile: file,
      );
    }
  }

  final ElkFfiBindings _bindings;

  @override
  final String engineDescription;

  @override
  String solve(String inputJson) {
    final result = _bindings.layoutJson(inputJson);
    final error = result.error;
    if (error != null) {
      throw LayoutException('elk rejected the layout input: $error');
    }
    return result.json!;
  }

  @override
  ElkSolveJob start(String inputJson) =>
      _NativeSolveJob(_bindings.startJob(inputJson));

  /// The library stays loaded for the process; there is nothing to release.
  @override
  void dispose() {}
}

/// [ElkSolveJob] over one `elk_ffi` job.
class _NativeSolveJob implements ElkSolveJob {
  _NativeSolveJob(this._job);

  final ElkFfiJob _job;

  @override
  ({bool done, LayoutProgress? progress}) poll() {
    final (:done, :progress) = _job.poll();
    final phase = LayoutPhase.fromCode(progress.phase);
    return (
      done: done,
      progress: phase == null
          ? null
          : LayoutProgress(phase: phase, fraction: progress.fraction),
    );
  }

  @override
  void cancel() => _job.cancel();

  @override
  String finish() {
    final result = _job.finish();
    if (result.cancelled) throw const LayoutCancelledException();
    final error = result.error;
    if (error != null) {
      throw LayoutException('elk rejected the layout input: $error');
    }
    return result.json!;
  }
}
