// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A reference to a span of text inside an RTL source file.
///
/// Sourced from elaboration / synthesis metadata (Yosys writes a
/// `src` attribute on every cell, port, and module, of the form
/// `path/to/file.v:line[.col]-line[.col]`). The [SourcePaneService]
/// owns parsing of that attribute into [SourceLocation]s.
///
/// [line] and [column] are 1-based to match how every text editor and
/// every error message renders source positions. [column] and
/// [lengthChars] are optional because some elaboration backends omit
/// column information.
@immutable
class SourceLocation {
  /// Creates a source-location reference.
  const SourceLocation({
    required this.filePath,
    required this.line,
    this.column,
    this.lengthChars,
  });

  /// Absolute or project-relative path to the source file.
  final String filePath;

  /// 1-based line number inside [filePath].
  final int line;

  /// 1-based column of the start of the span. Null when the
  /// elaboration backend did not record a column.
  final int? column;

  /// Length of the span in characters on [line]. Null when not
  /// recorded; renderers fall back to "highlight the whole line".
  final int? lengthChars;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceLocation &&
          other.filePath == filePath &&
          other.line == line &&
          other.column == column &&
          other.lengthChars == lengthChars);

  @override
  int get hashCode => Object.hash(filePath, line, column, lengthChars);

  @override
  String toString() {
    final col = column == null ? '' : ':$column';
    final len = lengthChars == null ? '' : '+$lengthChars';
    return 'SourceLocation($filePath:$line$col$len)';
  }
}
