// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_js/javascript_runtime.dart';
import 'package:flutter_js/javascriptcore/binding/js_context_ref.dart'
    show jSContextGetGroup;
import 'package:flutter_js/javascriptcore/binding/jsc_ffi.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';
import 'package:flutter_js/quickjs/ffi.dart' show runtimeOpaques;
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

/// How often, in seconds of the engine thread's CPU time, the
/// JavaScriptCore watchdog asks whether to stop the script (see
/// [_watchJavaScriptCore]). Short enough that Cancel stops an elkjs solve
/// at once as far as anyone can tell; long enough that the check costs
/// nothing measurable.
const double kJavaScriptCoreInterruptCheckSeconds = 0.1;

/// VM / desktop implementation of [ElkJsHost]. Wraps a flutter_js
/// [JavascriptRuntime] on the engine [selectLayoutEngine] picks, with the
/// handle that interrupts it from another isolate when the engine offers
/// one. Selected by the conditional import in `elk_layout_service.dart`
/// whenever `dart.library.io` is available.
class _FlutterJsHost implements InterruptibleElkJsHost {
  _FlutterJsHost(this._runtime, this.interruptHandle);
  final JavascriptRuntime _runtime;

  @override
  final ElkInterruptHandle? interruptHandle;

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
  ElkInterruptHandle? interrupt;
  switch (choice.engine) {
    case LayoutJsEngine.javaScriptCore:
      try {
        final jsc = _startJavaScriptCore(choice.library);
        runtime = jsc;
        interrupt = _watchJavaScriptCore(jsc);
      } on Object catch (e) {
        // A library that probed can still fail to start. The layout must
        // not: the interpreter is slower, not wrong.
        (runtime, interrupt) = _startQuickJs();
        description = 'QuickJS (JavaScriptCore failed to start: $e)';
      }
    case LayoutJsEngine.quickJs:
      (runtime, interrupt) = _startQuickJs();
  }
  stderr.writeln('netcrux: elkjs layout engine: $description');
  return _FlutterJsHost(runtime, interrupt);
}

/// Starts QuickJS with the stack budget [kQuickJsStackBytes], and returns
/// it with the handle that interrupts it: its `JSRuntime`, which
/// `interruptElkSolve` gives a one-byte stack budget. flutter_js keeps the
/// runtime pointer private but registers every runtime it creates in the
/// public `runtimeOpaques`, so the new key is this runtime's. No handle when
/// that registry does not show exactly one new runtime.
(JavascriptRuntime, ElkInterruptHandle?) _startQuickJs() {
  final before = runtimeOpaques.keys.toSet();
  final runtime = QuickJsRuntime2(stackSize: kQuickJsStackBytes);
  final created = runtimeOpaques.keys.where((rt) => !before.contains(rt));
  return (
    runtime,
    created.length == 1
        ? ElkInterruptHandle(
            ElkInterruptKind.quickJsStackLimit,
            created.single.address,
          )
        : null,
  );
}

typedef _ShouldTerminateNative =
    Bool Function(Pointer<Void> context, Pointer<Int32> flag);
typedef _SetExecutionTimeLimitNative =
    Void Function(
      Pointer<Void> group,
      Double limit,
      Pointer<NativeFunction<_ShouldTerminateNative>> callback,
      Pointer<Int32> flag,
    );
typedef _SetExecutionTimeLimitDart =
    void Function(
      Pointer<Void> group,
      double limit,
      Pointer<NativeFunction<_ShouldTerminateNative>> callback,
      Pointer<Int32> flag,
    );
typedef _CallocNative = Pointer<Void> Function(IntPtr count, IntPtr size);
typedef _CallocDart = Pointer<Void> Function(int count, int size);

/// `JSContextGroupSetExecutionTimeLimit`, bound on first use in this
/// isolate (after [_startJavaScriptCore] has pointed `JscFfi.lib` at the
/// library in use).
final _SetExecutionTimeLimitDart _setExecutionTimeLimit = JscFfi.lib
    .lookupFunction<_SetExecutionTimeLimitNative, _SetExecutionTimeLimitDart>(
      'JSContextGroupSetExecutionTimeLimit',
    );

/// [_shouldTerminate] as the C callback the watchdog calls.
final Pointer<NativeFunction<_ShouldTerminateNative>> _shouldTerminateCallback =
    Pointer.fromFunction<_ShouldTerminateNative>(_shouldTerminate, false);

/// Arms the watchdog of [group] for another [kJavaScriptCoreInterruptCheckSeconds]
/// with [flag].
void _armWatchdog(Pointer<Void> group, Pointer<Int32> flag) =>
    _setExecutionTimeLimit(
      group,
      kJavaScriptCoreInterruptCheckSeconds,
      _shouldTerminateCallback,
      flag,
    );

/// The JavaScriptCore watchdog's question, asked on the engine's own thread
/// while a script runs: stop when the flag is set. Otherwise the watchdog
/// is armed again here, since it does not re-arm itself after a callback
/// that declines.
bool _shouldTerminate(Pointer<Void> context, Pointer<Int32> flag) {
  if (flag.value != 0) return true;
  _armWatchdog(jSContextGetGroup(context).cast<Void>(), flag);
  return false;
}

/// Arms JavaScriptCore's watchdog on [runtime]'s context group and returns
/// the handle of the flag it reads, or `null` when the library does not
/// export `JSContextGroupSetExecutionTimeLimit`.
///
/// Every [kJavaScriptCoreInterruptCheckSeconds] of CPU time inside a script
/// the engine calls [_shouldTerminate] on the thread running the script;
/// while the flag is clear the script runs on. `interruptElkSolve` sets the
/// flag from another isolate, and the script then ends with an uncatchable
/// termination at the next check. The flag lives in C memory (four bytes,
/// never freed: the runtime it serves is never freed while its worker lives
/// either).
ElkInterruptHandle? _watchJavaScriptCore(JavascriptCoreRuntime runtime) {
  try {
    final calloc = DynamicLibrary.process()
        .lookupFunction<_CallocNative, _CallocDart>('calloc');
    final flag = calloc(1, sizeOf<Int32>()).cast<Int32>();
    if (flag == nullptr) return null;
    _armWatchdog(
      jSContextGetGroup(runtime.context.pointer).cast<Void>(),
      flag,
    );
    return ElkInterruptHandle(ElkInterruptKind.terminationFlag, flag.address);
  } on Object {
    return null;
  }
}

/// Starts JavaScriptCore, from [library] when given (Linux) or from the
/// system framework (macOS), and proves it evaluates before handing it out.
///
/// flutter_js resolves its JavaScriptCore bindings lazily from the handle in
/// `JscFfi.lib`, so replacing the handle before the first binding is touched
/// is enough to point the whole API at another library. That happens on the
/// worker isolate, whose statics are its own.
JavascriptCoreRuntime _startJavaScriptCore(String? library) {
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
