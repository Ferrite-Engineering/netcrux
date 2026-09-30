// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/source_token.dart';

/// The full text of an RTL source file plus optional lexer output.
///
/// Returned by [SourcePaneService.loadSource]. The renderer reads
/// [lines] to render line-by-line, [tokens] (when non-empty) to apply
/// per-token color and click-to-emit-selection behavior, and
/// [checksum] to invalidate caches when the underlying file changes.
@immutable
class SourceFileContent {
  /// Creates a loaded source-file content snapshot.
  const SourceFileContent({
    required this.filePath,
    required this.lines,
    required this.tokens,
    this.checksum = '',
  });

  /// An empty content snapshot — used by the open-core no-op service
  /// and as the initial value of any [SourceFileContent?] field that
  /// hasn't been populated yet.
  static const SourceFileContent empty = SourceFileContent(
    filePath: '',
    lines: <String>[],
    tokens: <SourceToken>[],
  );

  /// Absolute or project-relative path to the source file.
  final String filePath;

  /// The file's lines (with platform line endings normalised to `\n`,
  /// the trailing line preserved when the file ends in `\n`).
  final List<String> lines;

  /// Flat list of classified tokens across every line.
  ///
  /// Empty when the underlying [SourcePaneService] did not run a
  /// lexer (the open-core no-op service always returns empty); the
  /// renderer then falls back to plain monospace text.
  final List<SourceToken> tokens;

  /// Opaque checksum / version hint used to invalidate caches. Empty
  /// when the service did not compute one.
  final String checksum;

  /// True when this snapshot has no content.
  bool get isEmpty => lines.isEmpty;

  /// Number of lines in [lines].
  int get lineCount => lines.length;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SourceFileContent) return false;
    if (other.filePath != filePath) return false;
    if (other.checksum != checksum) return false;
    if (other.lines.length != lines.length) return false;
    if (other.tokens.length != tokens.length) return false;
    for (var i = 0; i < lines.length; i++) {
      if (other.lines[i] != lines[i]) return false;
    }
    for (var i = 0; i < tokens.length; i++) {
      if (other.tokens[i] != tokens[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    filePath,
    checksum,
    Object.hashAll(lines),
    Object.hashAll(tokens),
  );

  @override
  String toString() =>
      'SourceFileContent($filePath, $lineCount lines, '
      '${tokens.length} tokens)';
}
