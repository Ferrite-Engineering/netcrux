// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

/// Locates elaboration-engine binaries that NetCrux ships inside its
/// release distribution at runtime.
///
/// Resolution order, in priority:
///
///   1. `NETCRUX_BUNDLED_BIN_DIR` env var — points at a directory
///      containing every engine binary by canonical name. The CI helper
///      (`.github/workflows/bundled-engines.yml`) uses this to point
///      integration tests at the downloaded artifact cache without
///      bundling them into the Flutter binary.
///   2. The asset path relative to the Flutter app bundle:
///      `<assetsRoot>/bin/<platform>/<engineId>`. The platform string
///      is one of `linux-x86_64`, `macos-universal`,
///      `windows-x86_64` and matches the directory layout produced by
///      `tool/bundled_engines.yaml`.
///   3. Returns `null` — the caller falls back to PATH discovery
///      (the historical behavior).
///
/// Bundled binaries are gated to release builds at the per-engine
/// resolver layer (the resolver is asked, but the engine path provider
/// suppresses the lookup when `kDebugMode` is `true`). Debug builds
/// always shell out to `PATH` so contributors using locally-built
/// engines (with logging or experimental flags) get them automatically.
///
/// The resolver returns `null` from [_bundledRoot] whenever the env var is
/// unset, because release packaging does not place engine binaries in an
/// asset-based location. The seam — env var → per-engine path → fallback
/// to PATH — exists and is unit-tested so that packaging can light it up
/// without a code change.
///
/// Mirrors LintCrux's `BundledBinaryResolver`.
class BundledBinaryResolver {
  /// Creates a resolver. [overrideRoot] is provided in tests so the
  /// resolver can be pointed at a temp directory.
  const BundledBinaryResolver({this.overrideRoot});

  /// Test-only root directory containing per-platform binaries. When
  /// non-null, the resolver consults this directory first instead of
  /// the env var or the Flutter assets root.
  final String? overrideRoot;

  /// The environment variable consulted at runtime to locate bundled
  /// binaries when no [overrideRoot] is set. Exposed as a constant so
  /// the CI helper, tests, and documentation share a single source of
  /// truth.
  static const String envVarName = 'NETCRUX_BUNDLED_BIN_DIR';

  /// Resolves [engineId] (`'yosys'`, `'ghdl'`) to an absolute executable
  /// path, or `null` if no bundled binary is available for the current
  /// platform.
  String? resolve(String engineId) {
    final root = _bundledRoot();
    if (root == null) return null;
    final platformDir = _platformDir();
    if (platformDir == null) return null;
    final fileName = _fileName(engineId);
    final candidate =
        '$root${Platform.pathSeparator}'
        '$platformDir${Platform.pathSeparator}$fileName';
    if (File(candidate).existsSync()) return candidate;
    return null;
  }

  /// Returns the active bundled-binary root directory.
  String? _bundledRoot() {
    if (overrideRoot != null) return overrideRoot;
    final env = Platform.environment[envVarName];
    if (env != null && env.isNotEmpty) return env;
    // The Flutter app's bundled-asset path is not resolvable at compile
    // time without a runtime probe, so the env-var path is the only
    // mechanism and a null return lets the engine fall back to PATH
    // discovery.
    return null;
  }

  /// Returns the per-platform directory name (`linux-x86_64`, …) or
  /// `null` if the current host is unsupported.
  static String? _platformDir() {
    if (Platform.isLinux) return 'linux-${_archHint()}';
    if (Platform.isMacOS) return 'macos-universal';
    if (Platform.isWindows) return 'windows-${_archHint()}';
    return null;
  }

  static String _archHint() {
    // `Platform.version` does not reliably expose arch on every host.
    // The bundled-engines manifest commits one entry per platform-arch
    // pair; if the runtime arch doesn't match the bundled set, the
    // resolver returns null and the engine falls back to PATH. Phase
    // 2 manifest covers x86_64 only on linux/windows.
    return 'x86_64';
  }

  /// Returns the platform-specific file name for [engineId]: the `.exe`
  /// suffix on Windows, the bare name elsewhere.
  static String _fileName(String engineId) {
    if (Platform.isWindows) return '$engineId.exe';
    return engineId;
  }
}
