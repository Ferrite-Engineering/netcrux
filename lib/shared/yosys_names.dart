// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Readable forms of the cell and net names Yosys generates.
///
/// A generated name embeds the source path, line and a counter:
/// `$add$/src/rtl/gray_counter.v:14$3`, or for a net named after a cell's
/// output `$add$/src/rtl/gray_counter.v:15$5_Y`. [displayName] shortens that
/// to `$add  gray_counter.v:14` (and `$add  gray_counter.v:15  (Y)`), the way
/// the Netlist Diff View and the X-Trace panel show it.
///
/// Yosys writes a source path into a name with every space and other
/// unprintable character escaped as `$` and two hex digits, so a design in
/// `Getting Started` names its cells `...Getting$20Started...`. Those
/// escapes are part of the path, not separators between a name's parts.
abstract final class YosysNames {
  /// Whether [name] is one Yosys generated rather than one the user wrote.
  /// Yosys prefixes every generated cell and net name with `$`.
  static bool isGenerated(String name) => name.startsWith(r'$');

  /// [name] as a person would want to read it: a user-written name as is,
  /// a generated one as its cell type, `file:line` and, for a net named
  /// after a cell's pin, that pin in parentheses. A generated name of
  /// another shape (`$procmux$17_Y`, `$0\acc[35:0]`) keeps its form with
  /// any embedded source path cut to the file name.
  static String displayName(String name) {
    if (!isGenerated(name)) return name;
    final parsed = GeneratedName.parse(name);
    if (parsed == null) return withShortPaths(name);
    return <String>[parsed.type, parsed.location, ?parsed.pin].join('  ');
  }

  /// `file.v:14` from a Yosys source location such as
  /// `/abs/path/file.v:14.5-14.20`, or from a generated name embedding one
  /// (`$add$/abs/path/file.v:14$3`). Locations inside Yosys's own sources
  /// (`proc_dff.cc:220`) say nothing about the design and are skipped.
  /// Null when [text] has none.
  static String? shortSourceLocation(String? text) {
    if (text == null) return null;
    for (final m in _location.allMatches(text)) {
      final file = m.group(1)!;
      if (_yosysSource.hasMatch(file)) continue;
      return '${basename(file)}:${m.group(2)}';
    }
    return null;
  }

  /// [path] with each Yosys `$XX` hex escape replaced by the character it
  /// stands for: `Getting$20Started` is `Getting Started`.
  static String decodeEscapes(String path) => path.replaceAllMapped(
    _escape,
    (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
  );

  /// [name] with every embedded source path cut to its file name.
  static String withShortPaths(String name) => name.replaceAllMapped(
    _location,
    (m) => '${basename(m.group(1)!)}:${m.group(2)}',
  );

  /// The file name of [path], its escapes decoded.
  static String basename(String path) {
    final decoded = decodeEscapes(path);
    final cut = decoded.lastIndexOf(RegExp(r'[\\/]'));
    return cut < 0 ? decoded : decoded.substring(cut + 1);
  }

  /// Whether [path] is one of Yosys's own source files.
  static bool isYosysSource(String path) => _yosysSource.hasMatch(path);

  /// A `path/file.ext:line` run. The path may hold spaces and `$XX`
  /// escapes; any other `$` ends it, as does `|`: those delimit the parts of
  /// a generated name and of a multi-location `src`.
  static final RegExp _location = RegExp(
    r'((?:[^$|]|\$[0-9A-Fa-f]{2})+\.[A-Za-z0-9_]+):(\d+)',
  );

  static final RegExp _escape = RegExp(r'\$([0-9A-Fa-f]{2})');

  static final RegExp _yosysSource = RegExp(r'\.(cc|cpp|h)$');
}

/// The parts of a name Yosys generated for a cell or the net it drives:
/// `$<type>$<source path>:<line>$<counter><suffix>`, such as
/// `$add$/src/My$20Designs/counter.v:15$5_Y`.
final class GeneratedName {
  /// Creates the parts of a generated name.
  const GeneratedName({
    required this.type,
    required this.location,
    required this.pin,
  });

  /// Parses [name], or returns null when it is not of that shape (an
  /// `$auto$...` name from Yosys's own passes, `$procdff$12`,
  /// `$0\gray[7:0]`) or its source is one of Yosys's own files.
  static GeneratedName? parse(String name) {
    final m = _shape.firstMatch(name);
    if (m == null) return null;
    final path = m.group(2)!;
    if (YosysNames.isYosysSource(path)) return null;
    final suffix = m.group(4)!;
    return GeneratedName(
      type: m.group(1)!,
      location: '${YosysNames.basename(path)}:${m.group(3)}',
      pin: suffix.isEmpty
          ? null
          : '(${suffix.startsWith('_') ? suffix.substring(1) : suffix})',
    );
  }

  /// The cell type the name starts with: `$add`.
  final String type;

  /// `file.v:15`, the escapes decoded.
  final String location;

  /// `(Y)` for a net named after the cell's `Y` output; null for the cell
  /// itself.
  final String? pin;

  static final RegExp _shape = RegExp(
    r'^(\$[A-Za-z_][A-Za-z0-9_]*)\$((?:[^$]|\$[0-9A-Fa-f]{2})+\.[A-Za-z0-9_]+)'
    r':(\d+)\$\d+(.*)$',
  );
}
