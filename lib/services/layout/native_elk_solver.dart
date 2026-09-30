// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/layout/elk_ffi_bindings.dart';
import 'package:netcrux/services/layout/elk_ffi_library_io.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';

/// The desktop layout engine: the vendored elkrs port of the Eclipse Layout
/// Kernel, called through `native/elk_ffi`'s C ABI.
///
/// Same contract as the elkjs path, ELK JSON in and laid-out ELK JSON out,
/// and byte-identical output for NetCrux's inputs (the parity test holds it
/// to that), at native speed and memory: no JavaScript engine, no 1.6 MB
/// bundle to evaluate, no interpreter on Linux and Windows.
class NativeElkSolver implements ElkSolver {
  NativeElkSolver._(this._bindings, this.engineDescription);

  /// Opens the bundled library and binds its entry points. Throws when the
  /// library cannot be found or is the wrong build; the caller decides
  /// whether to fall back to elkjs.
  factory NativeElkSolver.open() {
    final bindings = ElkFfiBindings(openElkFfiLibrary());
    return NativeElkSolver._(bindings, 'native (${bindings.engineVersion()})');
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

  /// The library stays loaded for the process; there is nothing to release.
  @override
  void dispose() {}
}
