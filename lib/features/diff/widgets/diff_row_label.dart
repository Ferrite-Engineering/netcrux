// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/diff/diff_element_address.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';
import 'package:netcrux/shared/yosys_names.dart';

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
    final parsed = GeneratedName.parse(name);
    final location =
        shortSourceLocation(change.sourceLocation) ??
        parsed?.location ??
        shortSourceLocation(name);
    final String head;
    String? pin;
    if (change.elementKind == NetlistDiffElementKind.instance) {
      final snapshot = change.baselineSnapshot ?? change.comparisonSnapshot;
      head =
          snapshot?['type'] ?? parsed?.type ?? YosysNames.withShortPaths(name);
    } else if (parsed != null) {
      head = parsed.type;
      pin = parsed.pin;
    } else {
      head = YosysNames.withShortPaths(name);
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
  /// See [YosysNames.isGenerated].
  static bool isGeneratedName(String name) => YosysNames.isGenerated(name);

  /// `file.v:14` from a Yosys source location; see
  /// [YosysNames.shortSourceLocation].
  static String? shortSourceLocation(String? text) =>
      YosysNames.shortSourceLocation(text);

  /// [path] with each Yosys `$XX` hex escape decoded; see
  /// [YosysNames.decodeEscapes].
  static String decodeEscapes(String path) => YosysNames.decodeEscapes(path);

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
