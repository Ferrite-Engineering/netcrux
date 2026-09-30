// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Why a [SourcePaneService.loadSource] call failed.
enum SourceLoadFailure {
  /// The file does not exist at the requested path.
  notFound,

  /// The file exists but the process lacks permission to read it.
  accessDenied,

  /// The file's bytes could not be decoded as UTF-8 / the configured
  /// text encoding.
  encodingFailure,

  /// The file is larger than the service's size budget.
  oversized,

  /// Catch-all for unexpected I/O failures (disk error, etc.).
  ioError,
}

/// Thrown by [SourcePaneService.loadSource] when a source file cannot
/// be returned.
@immutable
class SourceLoadException implements Exception {
  /// Creates a load-failure exception.
  const SourceLoadException({
    required this.filePath,
    required this.reason,
    this.detail,
  });

  /// Path the caller tried to load.
  final String filePath;

  /// Categorical reason the load failed.
  final SourceLoadFailure reason;

  /// Optional free-text detail (an underlying I/O error message,
  /// etc.). Renderers may surface it in the error UI.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceLoadException &&
          other.filePath == filePath &&
          other.reason == reason &&
          other.detail == detail);

  @override
  int get hashCode => Object.hash(filePath, reason, detail);

  @override
  String toString() {
    final d = detail == null ? '' : ': $detail';
    return 'SourceLoadException($filePath, $reason$d)';
  }
}
