// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

/// A SystemVerilog construct Yosys's built-in reader (`read_verilog -sv`)
/// refuses although the language allows it.
///
/// Each is ordinary SystemVerilog-2017 that the yosys-slang front end reads.
/// Telling the user which one stopped the run, and that the tool rather than
/// the design is at fault, replaces a bare `syntax error, unexpected TOK_ID`.
enum SvFrontendGap {
  /// A `return` statement in a function.
  returnStatement,

  /// A package import inside a module, in its header
  /// (`module m import p::*; #(...)`) or its body.
  packageImport,

  /// A cast of a non-constant expression to a named type, such as
  /// `state_t'(x)` as a `case` expression.
  nonConstantCast,
}

/// Reads line [line] (1-based) of the file at [path], or returns `null` when
/// the file or the line cannot be read.
typedef SourceLineReader = String? Function(String path, int line);

String? _readSourceLine(String path, int line) {
  try {
    final lines = File(path).readAsLinesSync();
    return line >= 1 && line <= lines.length ? lines[line - 1] : null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

/// `<file>:<line>: ERROR: <message>`, the form Yosys's Verilog reader
/// reports a parse or elaboration error in.
final RegExp _errorLine = RegExp(
  r'^(.+?):(\d+): ERROR: (.*)$',
  multiLine: true,
);

/// The [SvFrontendGap] the first error in a failed run's [stderr] comes from,
/// or `null` when that error is anything else.
///
/// A `return` is recognised from the source text at the error's line, read
/// with [readLine] (the file system by default), because Yosys reports it as
/// a plain `unexpected TOK_ID`.
SvFrontendGap? svFrontendGapIn(
  String stderr, {
  SourceLineReader readLine = _readSourceLine,
}) {
  final match = _errorLine.firstMatch(stderr);
  if (match == null) return null;
  final message = match.group(3)!;
  if (message.startsWith('Static cast with non constant expression')) {
    return SvFrontendGap.nonConstantCast;
  }
  if (message.contains('unexpected TOK_IMPORT')) {
    return SvFrontendGap.packageImport;
  }
  if (message.contains('unexpected TOK_ID')) {
    final source = readLine(match.group(1)!, int.parse(match.group(2)!));
    if (source != null && RegExp(r'^\s*return\b').hasMatch(source)) {
      return SvFrontendGap.returnStatement;
    }
  }
  return null;
}
