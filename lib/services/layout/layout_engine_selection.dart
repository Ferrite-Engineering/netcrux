// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Which JavaScript engine the desktop layout host runs elkjs on.
///
/// The choice decides whether a large scope lays out in seconds or times
/// out: elkjs is a GWT-transpiled Java layout kernel, and the same script
/// runs an order of magnitude or more slower on an interpreter than on a
/// JIT engine. flutter_js's own selector picks JavaScriptCore on macOS and
/// QuickJS on Linux and Windows; [selectLayoutEngine] widens that to
/// JavaScriptCore on Linux whenever WebKitGTK's library is installed.
enum LayoutJsEngine {
  /// JavaScriptCore: Apple's engine, a JIT. The system framework on macOS;
  /// on Linux the library WebKitGTK ships, when present.
  javaScriptCore,

  /// QuickJS: the small interpreter flutter_js bundles for Linux and
  /// Windows. Always available, many times slower than a JIT on a large
  /// scope.
  quickJs,
}

/// The host operating system, as far as engine selection cares.
enum LayoutHostPlatform {
  /// macOS: JavaScriptCore is the system framework.
  macOS,

  /// Linux: JavaScriptCore when a WebKitGTK library probes, else QuickJS.
  linux,

  /// Windows: QuickJS. No system JavaScriptCore exists.
  windows,

  /// Anything else: QuickJS.
  other,
}

/// Environment variable that overrides the selection for diagnosis and
/// support: `quickjs` forces the interpreter, `jsc` or `javascriptcore`
/// asks for JavaScriptCore (still falling back when no library loads). The
/// engine actually started is announced on stderr when the worker starts.
const String kLayoutEngineEnvVar = 'NETCRUX_LAYOUT_ENGINE';

/// Linux library names probed for JavaScriptCore, newest ABI first. Each
/// distribution ships one or two of these: Debian and Ubuntu 22.04 carry the
/// 4.0 and 4.1 lines, Ubuntu 24.04 and Fedora the 4.1 and 6.0 lines.
const List<String> kLinuxJavaScriptCoreLibraries = <String>[
  'libjavascriptcoregtk-6.0.so.1',
  'libjavascriptcoregtk-4.1.so.0',
  'libjavascriptcoregtk-4.0.so.18',
];

/// The outcome of [selectLayoutEngine].
class LayoutEngineChoice {
  /// Creates a choice of [engine].
  const LayoutEngineChoice(
    this.engine, {
    this.library,
    this.forced = false,
    this.note,
  });

  /// The engine to start.
  final LayoutJsEngine engine;

  /// The Linux library that satisfied the probe. `null` for the macOS system
  /// framework and for QuickJS.
  final String? library;

  /// Whether [kLayoutEngineEnvVar] made the choice.
  final bool forced;

  /// Why the choice differs from what was asked for, when it does.
  final String? note;

  /// One line for the stderr announcement.
  String describe() {
    final name = switch (engine) {
      LayoutJsEngine.javaScriptCore => 'JavaScriptCore',
      LayoutJsEngine.quickJs => 'QuickJS',
    };
    final buffer = StringBuffer(name);
    if (library != null) buffer.write(' ($library)');
    if (forced) buffer.write(', forced by $kLayoutEngineEnvVar');
    if (note != null) buffer.write('; $note');
    return buffer.toString();
  }
}

/// Chooses the engine for [platform].
///
/// [probe] answers whether a named library can be opened and exports the
/// JavaScriptCore C API. It is consulted only on Linux, in
/// [kLinuxJavaScriptCoreLibraries] order, and must not throw: the caller
/// maps every failure to `false`, and a probe that lies is caught later by
/// the host's smoke evaluation, which falls back to QuickJS.
LayoutEngineChoice selectLayoutEngine({
  required LayoutHostPlatform platform,
  required Map<String, String> environment,
  required bool Function(String libraryName) probe,
}) {
  final requested = environment[kLayoutEngineEnvVar]?.trim().toLowerCase();
  if (requested == 'quickjs') {
    return const LayoutEngineChoice(LayoutJsEngine.quickJs, forced: true);
  }
  final wantsJsc = requested == 'jsc' || requested == 'javascriptcore';
  switch (platform) {
    case LayoutHostPlatform.macOS:
      return LayoutEngineChoice(
        LayoutJsEngine.javaScriptCore,
        forced: wantsJsc,
      );
    case LayoutHostPlatform.linux:
      for (final name in kLinuxJavaScriptCoreLibraries) {
        if (probe(name)) {
          return LayoutEngineChoice(
            LayoutJsEngine.javaScriptCore,
            library: name,
            forced: wantsJsc,
          );
        }
      }
      return LayoutEngineChoice(
        LayoutJsEngine.quickJs,
        note: wantsJsc
            ? '$kLayoutEngineEnvVar asked for JavaScriptCore, but no '
                  'libjavascriptcoregtk library could be loaded'
            : null,
      );
    case LayoutHostPlatform.windows:
    case LayoutHostPlatform.other:
      return LayoutEngineChoice(
        LayoutJsEngine.quickJs,
        note: wantsJsc
            ? '$kLayoutEngineEnvVar asked for JavaScriptCore, which this '
                  'platform does not provide'
            : null,
      );
  }
}

/// Which solver the desktop layout worker runs.
enum LayoutSolverKind {
  /// The vendored elkrs port of ELK through `native/elk_ffi`. The default.
  native,

  /// The vendored elkjs bundle on a JavaScript engine ([LayoutJsEngine]).
  /// Kept for one release as an escape hatch and as the parity reference.
  elkjs,
}

/// Decides between the native engine and elkjs from the value of
/// [kLayoutEngineEnvVar], [requested]. `elkjs` keeps elkjs on the default
/// JavaScript engine; `jsc`, `javascriptcore` and `quickjs` keep elkjs on
/// that engine ([selectLayoutEngine] reads the same value). Anything else,
/// including nothing, is the native engine.
LayoutSolverKind selectLayoutSolver({required String? requested}) {
  return switch (requested?.trim().toLowerCase()) {
    'elkjs' || 'jsc' || 'javascriptcore' || 'quickjs' => LayoutSolverKind.elkjs,
    _ => LayoutSolverKind.native,
  };
}
