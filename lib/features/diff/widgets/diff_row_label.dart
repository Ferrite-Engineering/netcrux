// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/diff/diff_element_address.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';

/// What a Netlist Diff View row shows for one [ElementChange].
///
/// A user-named element shows its name, with the full path beneath. A
/// Yosys-generated one (a name starting with `$`) would show something like
/// `$add$/src/rtl/gray_counter.v:14$3`, so it shows its cell type and
/// `file:line` instead (`$add  gray_counter.v:14`), with the module beneath.
/// A generated net reads the same way, plus the pin of the cell it was
/// named after: `$add$/src/rtl/gray_counter.v:15$5_Y` shows as
/// `$add  gray_counter.v:15  (Y)`. The full name always stays in [tooltip].
///
/// Yosys writes a source path into a name with every space and other
/// unprintable character escaped as `$` and two hex digits, so a design in
/// `Getting Started` names its cells `...Getting$20Started...`. Those
/// escapes are part of the path, not separators between a name's parts.
@immutable
class DiffRowLabel {
  /// Creates a label.
  const DiffRowLabel({
    required this.title,
    required this.subtitle,
    required this.tooltip,
  });

  /// Builds the label for [change].
  factory DiffRowLabel.of(ElementChange change) {
    final path = change.elementId.path;
    final address = DiffElementAddress.parse(change.elementKind, path);
    final name = address?.name ?? path;
    final tooltip = <String>[
      path,
      if (change.comparisonName != null) '= ${change.comparisonName}',
      ?change.sourceLocation,
    ].join('\n');
    if (!isGeneratedName(name)) {
      return DiffRowLabel(title: name, subtitle: path, tooltip: tooltip);
    }
    final parsed = _GeneratedName.parse(name);
    final location =
        shortSourceLocation(change.sourceLocation) ??
        parsed?.location ??
        shortSourceLocation(name);
    final String head;
    String? pin;
    if (change.elementKind == NetlistDiffElementKind.instance) {
      final snapshot = change.baselineSnapshot ?? change.comparisonSnapshot;
      head = snapshot?['type'] ?? parsed?.type ?? _withShortPaths(name);
    } else if (parsed != null) {
      head = parsed.type;
      pin = parsed.pin;
    } else {
      head = _withShortPaths(name);
    }
    final showLocation = location != null && !head.contains(location);
    return DiffRowLabel(
      title: <String>[head, if (showLocation) location, ?pin].join('  '),
      subtitle: address?.module ?? path,
      tooltip: tooltip,
    );
  }

  /// The row's main line.
  final String title;

  /// The smaller line beneath [title].
  final String subtitle;

  /// The full path, the comparison-side name when it differs, and the
  /// source location: everything [title] shortens.
  final String tooltip;

  /// Whether [name] is one Yosys generated rather than one the user wrote.
  /// Yosys prefixes every generated cell and net name with `$`.
  static bool isGeneratedName(String name) => name.startsWith(r'$');

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
      return '${_basename(file)}:${m.group(2)}';
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
  static String _withShortPaths(String name) => name.replaceAllMapped(
    _location,
    (m) => '${_basename(m.group(1)!)}:${m.group(2)}',
  );

  static String _basename(String path) {
    final decoded = decodeEscapes(path);
    final cut = decoded.lastIndexOf(RegExp(r'[\\/]'));
    return cut < 0 ? decoded : decoded.substring(cut + 1);
  }

  /// A `path/file.ext:line` run. The path may hold spaces and `$XX`
  /// escapes; any other `$` ends it, as does `|`: those delimit the parts of
  /// a generated name and of a multi-location `src`.
  static final RegExp _location = RegExp(
    r'((?:[^$|]|\$[0-9A-Fa-f]{2})+\.[A-Za-z0-9_]+):(\d+)',
  );

  static final RegExp _escape = RegExp(r'\$([0-9A-Fa-f]{2})');

  static final RegExp _yosysSource = RegExp(r'\.(cc|cpp|h)$');

  @override
  bool operator ==(Object other) =>
      other is DiffRowLabel &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.tooltip == tooltip;

  @override
  int get hashCode => Object.hash(title, subtitle, tooltip);

  @override
  String toString() => 'DiffRowLabel($title | $subtitle)';
}

/// The parts of a name Yosys generated for a cell or the net it drives:
/// `$<type>$<source path>:<line>$<counter><suffix>`, such as
/// `$add$/src/My$20Designs/counter.v:15$5_Y`.
class _GeneratedName {
  const _GeneratedName({
    required this.type,
    required this.location,
    required this.pin,
  });

  /// Parses [name], or returns null when it is not of that shape (an
  /// `$auto$...` name from Yosys's own passes, `$procdff$12`,
  /// `$0\gray[7:0]`) or its source is one of Yosys's own files.
  static _GeneratedName? parse(String name) {
    final m = _shape.firstMatch(name);
    if (m == null) return null;
    final path = m.group(2)!;
    if (DiffRowLabel._yosysSource.hasMatch(path)) return null;
    final suffix = m.group(4)!;
    return _GeneratedName(
      type: m.group(1)!,
      location: '${DiffRowLabel._basename(path)}:${m.group(3)}',
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
