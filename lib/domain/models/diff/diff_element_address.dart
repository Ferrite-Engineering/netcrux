// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';

/// The module and element name an [ElementChange] row's path names.
///
/// The diff service writes one path shape per element kind:
///
/// | Kind | Path |
/// |---|---|
/// | instance | `<module>.<cell>:cell` |
/// | net | `<module>:net:<net>` |
/// | port | `<module>.<port>` |
/// | module | `<module>:module` |
///
/// The element name is everything after the module, never the text after
/// the last dot: Yosys names the cells and nets it generates after their
/// source file (`$add$/src/counter.v:14$3`), so a name routinely contains
/// dots, slashes and colons. Splitting on the last dot is what made Show in
/// Schematic look for a cell named `v:14$3`.
@immutable
class DiffElementAddress {
  /// Creates an address.
  const DiffElementAddress({required this.module, required this.name});

  /// Parses [path], written for [kind]. Returns null for a path of another
  /// shape.
  static DiffElementAddress? parse(NetlistDiffElementKind kind, String path) {
    switch (kind) {
      case NetlistDiffElementKind.module:
        const suffix = ':module';
        if (!path.endsWith(suffix)) return null;
        final module = path.substring(0, path.length - suffix.length);
        if (module.isEmpty) return null;
        return DiffElementAddress(module: module, name: module);
      case NetlistDiffElementKind.net:
        const marker = ':net:';
        final at = path.indexOf(marker);
        if (at <= 0) return null;
        final name = path.substring(at + marker.length);
        if (name.isEmpty) return null;
        return DiffElementAddress(module: path.substring(0, at), name: name);
      case NetlistDiffElementKind.instance:
        const suffix = ':cell';
        if (!path.endsWith(suffix)) return null;
        return _splitAtFirstDot(path.substring(0, path.length - suffix.length));
      case NetlistDiffElementKind.port:
        return _splitAtFirstDot(path);
    }
  }

  static DiffElementAddress? _splitAtFirstDot(String path) {
    final dot = path.indexOf('.');
    if (dot <= 0 || dot == path.length - 1) return null;
    return DiffElementAddress(
      module: path.substring(0, dot),
      name: path.substring(dot + 1),
    );
  }

  /// The module the element is declared in.
  final String module;

  /// The element's own name inside [module]: the cell, net or port name,
  /// or the module name again for a module row.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is DiffElementAddress &&
      other.module == module &&
      other.name == name;

  @override
  int get hashCode => Object.hash(module, name);

  @override
  String toString() => 'DiffElementAddress($module, $name)';
}
