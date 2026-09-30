// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_js/javascript_runtime.dart';
import 'package:flutter_js/javascriptcore/binding/jsc_ffi.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';
import 'package:flutter_js/quickjs/quickjs_runtime2.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/layout_engine_selection.dart';

/// QuickJS's stack budget, in bytes.
///
/// QuickJS runs every JavaScript call as a C-level recursion and stops with
/// a catchable "stack overflow" once its own accounting passes this budget.
/// flutter_js's default is 1 MiB, which is no smaller than the stack of the
/// Dart worker thread the engine runs on, so a deep recursion (ELK's
/// depth-first cycle breaker on a thousand-cell chain) overran the real
/// stack before the budget tripped and took the process down with SIGSEGV.
/// Half the thread stack leaves the Dart frames beneath the engine their
/// room and turns the same overflow into a [LayoutException].
const int kQuickJsStackBytes = 512 * 1024;

/// VM / desktop implementation of [ElkJsHost]. Wraps a flutter_js
/// [JavascriptRuntime] on the engine [selectLayoutEngine] picks. Selected by
/// the conditional import in `elk_layout_service.dart` whenever
/// `dart.library.io` is available.
class _FlutterJsHost implements ElkJsHost {
  _FlutterJsHost(this._runtime);
  final JavascriptRuntime _runtime;

  @override
  String evaluate(String code) => _runtime.evaluate(code).stringResult;

  @override
  int executePendingJob() {
    _runtime.executePendingJob();
    return 0;
  }

  @override
  void dispose() => _runtime.dispose();
}

/// Returns a fresh flutter_js-backed host on the engine chosen for this
/// platform, and announces the choice on stderr (the CLIs parse stdout).
///
/// The runtimes are constructed directly rather than through
/// `getJavascriptRuntime()`: that helper hard-codes QuickJS on Linux, and its
/// `enableFetch()` reads a polyfill through `rootBundle`, which has no
/// binding on a worker isolate and surfaced as the "Binding has not yet
/// been initialized" error the isolate drains. elkjs needs neither fetch nor
/// flutter_js's promise helpers; the layout driver polyfills what it uses.
ElkJsHost createDefaultElkJsHost() {
  final choice = selectLayoutEngine(
    platform: _currentPlatform(),
    environment: Platform.environment,
    probe: _exportsJavaScriptCoreApi,
  );
  var description = choice.describe();
  JavascriptRuntime runtime;
  switch (choice.engine) {
    case LayoutJsEngine.javaScriptCore:
      try {
        runtime = _startJavaScriptCore(choice.library);
      } on Object catch (e) {
        // A library that probed can still fail to start. The layout must
        // not: the interpreter is slower, not wrong.
        runtime = QuickJsRuntime2(stackSize: kQuickJsStackBytes);
        description = 'QuickJS (JavaScriptCore failed to start: $e)';
      }
    case LayoutJsEngine.quickJs:
      runtime = QuickJsRuntime2(stackSize: kQuickJsStackBytes);
  }
  stderr.writeln('netcrux: elkjs layout engine: $description');
  return _FlutterJsHost(runtime);
}

/// Starts JavaScriptCore, from [library] when given (Linux) or from the
/// system framework (macOS), and proves it evaluates before handing it out.
///
/// flutter_js resolves its JavaScriptCore bindings lazily from the handle in
/// `JscFfi.lib`, so replacing the handle before the first binding is touched
/// is enough to point the whole API at another library. That happens on the
/// worker isolate, whose statics are its own.
JavascriptRuntime _startJavaScriptCore(String? library) {
  if (library != null) JscFfi.lib = DynamicLibrary.open(library);
  final runtime = JavascriptCoreRuntime();
  final probe = runtime.evaluate('1 + 1').stringResult;
  if (probe != '2') {
    runtime.dispose();
    throw StateError('smoke evaluation returned "$probe"');
  }
  return runtime;
}

LayoutHostPlatform _currentPlatform() {
  if (Platform.isMacOS) return LayoutHostPlatform.macOS;
  if (Platform.isLinux) return LayoutHostPlatform.linux;
  if (Platform.isWindows) return LayoutHostPlatform.windows;
  return LayoutHostPlatform.other;
}

/// Whether [library] can be opened and exports the classic JavaScriptCore
/// C API the bindings use. Never throws.
bool _exportsJavaScriptCoreApi(String library) {
  try {
    DynamicLibrary.open(
      library,
    ).lookup<NativeFunction<Void Function()>>('JSEvaluateScript');
    return true;
  } on Object {
    return false;
  }
}
