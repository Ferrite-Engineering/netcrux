// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';

/// Builds the canonical dot-joined hierarchical path for the schematic
/// element [element] sitting inside [scope].
///
/// The path follows the netcrux convention shared with WaveCrux's
/// signal naming: `<topModule>.<instance>.<instance>…<leaf>`, where
///
/// - [topModuleName] is the leftmost segment so paths copied into
///   chat / docs round-trip the module name an engineer types
///   (resolved by the caller from `NetlistModel.topModule.name`);
/// - intermediate segments are the instance names along
///   [HierarchyNode.path];
/// - the trailing segment depends on [element]'s kind:
///   - cell → cell instance name (`cellId` minus any synthetic
///     punctuation), tagged `:cell`;
///   - port → cell instance name + `.` + port name, no tag;
///   - boundary port → `:port:<name>` (the scope itself is the parent
///     module, so we mark the leaf explicitly);
///   - wire → `:net:<edgeId>`.
///
/// Empty selection returns `null`. The path string is locale-stable
/// (no localization) because it's the over-the-wire form for
/// cross-tool cross-probing (CXP) and for the
/// "Copy Path" clipboard action.
String? buildElementPath({
  required String topModuleName,
  required HierarchyNode scope,
  required SelectedElement element,
}) {
  final scopePrefix = <String>[topModuleName, ...scope.path].join('.');
  return switch (element) {
    SelectedElementNone() => null,
    SelectedElementCell(:final cellId) => '$scopePrefix.$cellId:cell',
    SelectedElementPort(:final cellId, :final portName) =>
      '$scopePrefix.$cellId.$portName',
    SelectedElementBoundaryPort(:final portName) =>
      '$scopePrefix:port:$portName',
    SelectedElementWire(:final edgeId) => '$scopePrefix:net:$edgeId',
  };
}
