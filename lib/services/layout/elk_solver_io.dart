// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_js/quickjs/ffi.dart' show JSRuntime, jsSetMaxStackSize;
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/flutter_js_host_vm.dart';
import 'package:netcrux/services/layout/layout_engine_selection.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';

/// Desktop implementation of [createDefaultElkSolver]: the native engine
/// unless `NETCRUX_LAYOUT_ENGINE` keeps elkjs or the native library cannot
/// start, in which case elkjs runs on whatever JavaScript engine
/// [createDefaultElkJsHost] picks. [solver] overrides the environment: the
/// native engine, throwing when it cannot start (the service's retry of a
/// scope elkjs ran out of stack on), or elkjs. Announces the engine on
/// stderr (the CLIs parse stdout). Selected by the conditional import in
/// `elk_layout_service.dart` whenever `dart.library.io` is available.
ElkSolver createDefaultElkSolver(String elkSource, {LayoutSolverKind? solver}) {
  if (solver == LayoutSolverKind.native) {
    final native = NativeElkSolver.open();
    stderr.writeln(
      'netcrux: layout engine: ${native.engineDescription}, in place of '
      'elkjs, which ran out of stack on a scope',
    );
    return native;
  }
  final requested = Platform.environment[kLayoutEngineEnvVar];
  var note = '';
  if (solver == LayoutSolverKind.elkjs) {
    note = ' (requested by the caller)';
  } else if (selectLayoutSolver(requested: requested) ==
      LayoutSolverKind.native) {
    try {
      final solver = NativeElkSolver.open();
      stderr.writeln('netcrux: layout engine: ${solver.engineDescription}');
      return solver;
    } on Object catch (e) {
      // The library is bundled with every desktop build, so this is a
      // broken installation, not a configuration; say so and keep working.
      note = ' (native engine unavailable: $e)';
    }
  } else {
    note = ' (kept by $kLayoutEngineEnvVar)';
  }
  final host = createDefaultElkJsHost();
  initElkRuntime(host, elkSource);
  stderr.writeln('netcrux: layout engine: elkjs$note');
  return JsElkSolver(host);
}

/// Desktop implementation of [interruptElkSolve]: makes the elkjs solve
/// another isolate is running stop at the engine's next check.
///
/// QuickJS: the runtime's stack budget drops to one byte, so the next
/// JavaScript call throws "stack overflow" and the script unwinds within
/// microseconds. The budget is two words in the runtime that only the
/// engine's own stack checks read, and the runtime is never freed while its
/// worker lives (a killed worker leaks it), so the write cannot land on
/// freed memory. JavaScriptCore: sets the flag its watchdog callback reads
/// on the engine's thread (see `flutter_js_host_vm.dart`).
void interruptElkSolve(ElkInterruptHandle handle) {
  switch (handle.kind) {
    case ElkInterruptKind.quickJsStackLimit:
      jsSetMaxStackSize(Pointer<JSRuntime>.fromAddress(handle.address), 1);
    case ElkInterruptKind.terminationFlag:
      Pointer<Int32>.fromAddress(handle.address).value = 1;
  }
}
