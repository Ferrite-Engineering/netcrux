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
/// `$add$/src/rtl/gray_counter.v:14$3`, so it shows its cell
/// type and `file:line` instead (`$add  gray_counter.v:14`), with the
/// module beneath. The full name always stays in [tooltip].
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
    final location =
        shortSourceLocation(change.sourceLocation) ?? shortSourceLocation(name);
    final String head;
    if (change.elementKind == NetlistDiffElementKind.instance) {
      final snapshot = change.baselineSnapshot ?? change.comparisonSnapshot;
      head = snapshot?['type'] ?? _withShortPaths(name);
    } else {
      head = _withShortPaths(name);
    }
    final showLocation = location != null && !head.contains(location);
    return DiffRowLabel(
      title: showLocation ? '$head  $location' : head,
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

  /// [name] with every embedded source path cut to its file name.
  static String _withShortPaths(String name) => name.replaceAllMapped(
    _location,
    (m) => '${_basename(m.group(1)!)}:${m.group(2)}',
  );

  static String _basename(String path) {
    final cut = path.lastIndexOf(RegExp(r'[\\/]'));
    return cut < 0 ? path : path.substring(cut + 1);
  }

  /// A `path/file.ext:line` run. The path may hold spaces; it stops at `$`
  /// and `|`, which delimit the parts of a generated name and of a
  /// multi-location `src`.
  static final RegExp _location = RegExp(r'([^$|]+\.[A-Za-z0-9_]+):(\d+)');

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
