// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';

/// Desktop implementation of [createDefaultElkSolver]: the native engine,
/// the vendored elkrs port through `native/elk_ffi`. Announces the engine on
/// stderr (the CLIs parse stdout). There is no other engine to fall back
/// to: when the library cannot be loaded this throws the
/// [LayoutFailureKind.engineUnavailable] [LayoutException] of
/// [NativeElkSolver.open], which names the file. Selected by the conditional
/// import in `elk_layout_service.dart` whenever `dart.library.io` is
/// available.
ElkSolver createDefaultElkSolver() {
  final solver = NativeElkSolver.open();
  stderr.writeln('netcrux: layout engine: ${solver.engineDescription}');
  return solver;
}
