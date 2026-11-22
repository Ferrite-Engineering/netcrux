// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/layout_engine_selection.dart';

/// Placeholder for platforms without `dart:io`. The browser never reaches
/// it: the web edition awaits elkjs's own Promise in `elk_web_solver_web.dart`
/// before the worker path is considered.
ElkSolver createDefaultElkSolver(String elkSource, {LayoutSolverKind? solver}) {
  throw UnsupportedError(
    'createDefaultElkSolver is not available on this platform; the '
    'conditional import in elk_layout_service.dart should route to '
    'elk_solver_io.dart.',
  );
}
