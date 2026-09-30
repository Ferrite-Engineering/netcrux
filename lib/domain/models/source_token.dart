// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';

/// Classification of a single token in a rendered RTL source line.
///
/// Coarse on purpose — the source pane is a read-only viewer, not a
/// full editor, and the lexer that produces these spans (in the Pro
/// overlay) is a basic keyword classifier rather than a full
/// Verilog/SystemVerilog/VHDL parser. The kinds map to color buckets in
/// the open-core renderer.
enum SourceTokenKind {
  /// Reserved language keyword (`module`, `endmodule`, `always`, etc.).
  keyword,

  /// Identifier (module name, signal name, port name, label).
  ///
  /// Identifiers whose name corresponds to a known schematic element
  /// also carry an [SourceToken.associatedElementId]; the renderer
  /// turns those into tappable spans that emit a selection back into
  /// the schematic.
  identifier,

  /// Numeric literal (`32'hDEAD_BEEF`, `8'b1010`, `42`).
  number,

  /// String literal (`"hello"`).
  string,

  /// Comment (`// ...`, `/* ... */`, `-- ...`).
  comment,

  /// Operator or punctuation (`+`, `==`, `<=`, `(`, `)`, `;`).
  operator,

  /// Whitespace run between tokens.
  whitespace,

  /// Anything the lexer didn't classify. Renders in the default text
  /// style.
  unknown,
}

/// A classified span of text on a single line of an RTL source file.
///
/// Lines are decomposed into a flat list of [SourceToken]s by the
/// [SourcePaneService]. The renderer reads each token's [kind] to
/// pick a color and renders [associatedElementId]-carrying tokens as
/// tappable spans (clicking emits a selection into the schematic).
@immutable
class SourceToken {
  /// Creates a token span.
  const SourceToken({
    required this.line,
    required this.columnStart,
    required this.columnEnd,
    required this.kind,
    this.associatedElementId,
  });

  /// 1-based line number this token lives on.
  final int line;

  /// 1-based column of the first character of the token.
  final int columnStart;

  /// 1-based column one past the last character of the token. The
  /// renderer extracts the text via `line.substring(columnStart - 1,
  /// columnEnd - 1)`.
  final int columnEnd;

  /// Classification of the token.
  final SourceTokenKind kind;

  /// Canonical [ElementId] (from `package:crux_cxp`) that this token
  /// resolves to in the schematic, when the lexer was able to map it.
  ///
  /// Non-null tokens render as tappable spans; tapping dispatches a
  /// selection back into the schematic. Null tokens render as
  /// non-interactive text.
  final ElementId? associatedElementId;

  /// Width of the token in characters.
  int get widthChars => columnEnd - columnStart;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceToken &&
          other.line == line &&
          other.columnStart == columnStart &&
          other.columnEnd == columnEnd &&
          other.kind == kind &&
          other.associatedElementId == associatedElementId);

  @override
  int get hashCode => Object.hash(
    line,
    columnStart,
    columnEnd,
    kind,
    associatedElementId,
  );

  @override
  String toString() =>
      'SourceToken(line $line, $columnStart..$columnEnd, $kind'
      '${associatedElementId == null ? '' : ', $associatedElementId'})';
}
