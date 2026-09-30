// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/layout/elk_layout_service.dart';

/// Placeholder for platforms without `dart:io`. The browser never reaches
/// it: the web edition awaits elkjs's own Promise in `elk_web_solver_web.dart`
/// before the worker path is considered.
ElkSolver createDefaultElkSolver(String elkSource) {
  throw UnsupportedError(
    'createDefaultElkSolver is not available on this platform; the '
    'conditional import in elk_layout_service.dart should route to '
    'elk_solver_io.dart.',
  );
}
