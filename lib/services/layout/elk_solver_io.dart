// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/flutter_js_host_vm.dart';
import 'package:netcrux/services/layout/layout_engine_selection.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';

/// Desktop implementation of [createDefaultElkSolver]: the native engine
/// unless `NETCRUX_LAYOUT_ENGINE` keeps elkjs or the native library cannot
/// start, in which case elkjs runs on whatever JavaScript engine
/// [createDefaultElkJsHost] picks. Announces the engine on stderr (the CLIs
/// parse stdout). Selected by the conditional import in
/// `elk_layout_service.dart` whenever `dart.library.io` is available.
ElkSolver createDefaultElkSolver(String elkSource) {
  final requested = Platform.environment[kLayoutEngineEnvVar];
  var note = '';
  if (selectLayoutSolver(requested: requested) == LayoutSolverKind.native) {
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
