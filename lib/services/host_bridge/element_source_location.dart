// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/source_location.dart';

/// The source locations a Yosys `src` attribute names.
///
/// Yosys writes `file:line.col-line.col` for a span over several lines,
/// `file:line.col-col` for a span on one line, and `a.v:1.1-2.2|b.v:3.1-4.2`
/// when a node comes from several places. A location in Yosys's own sources
/// (`proc_dff.cc:220`) says nothing about the design and is skipped. The
/// returned locations keep the attribute's order.
List<SourceLocation> parseYosysSrc(String? src) {
  if (src == null || src.isEmpty) return const <SourceLocation>[];
  final out = <SourceLocation>[];
  for (final part in src.split('|')) {
    final match = _span.firstMatch(part.trim());
    if (match == null) continue;
    final file = match.group(1)!;
    if (_yosysOwnSource.hasMatch(file)) continue;
    final line = int.tryParse(match.group(2)!);
    if (line == null || line < 1) continue;
    final column = int.tryParse(match.group(3) ?? '');
    out.add(
      SourceLocation(
        filePath: file,
        line: line,
        column: column != null && column >= 1 ? column : null,
      ),
    );
  }
  return out;
}

/// A file of Yosys's own sources (`proc_dff.cc:220`), which says nothing about
/// the design.
final RegExp _yosysOwnSource = RegExp(r'\.(cc|cpp|h)$');

/// `file`, `line`, optional `.col`, optional `-endLine.endCol` or `-endCol`.
final RegExp _span = RegExp(r'^(.+):(\d+)(?:\.(\d+))?(?:-\d+(?:\.\d+)?)?$');

/// Where [element] of [module] comes from in the RTL, or null when the netlist
/// records no source for it.
///
/// A cell and a pin take the cell's `src`; a wire takes its net's; a boundary
/// port, which has no attributes of its own, takes the module's.
SourceLocation? sourceLocationOfElement(
  Module module,
  SelectedElement element,
) {
  final String? src;
  switch (element) {
    case SelectedElementNone():
      src = null;
    case SelectedElementCell(:final cellId):
      src = module.cells[cellId]?.attributes['src'];
    case SelectedElementPort(:final cellId):
      src = module.cells[cellId]?.attributes['src'];
    case SelectedElementBoundaryPort():
      src = module.attributes['src'];
    case SelectedElementWire(:final netId):
      src = _netOf(module, netId)?.attributes['src'];
  }
  return parseYosysSrc(src).firstOrNull;
}

Net? _netOf(Module module, int netId) {
  for (final net in module.nets.values) {
    for (final bit in net.bits) {
      final value = bit.toJson();
      if (value is int && value == netId) return net;
    }
  }
  return null;
}
