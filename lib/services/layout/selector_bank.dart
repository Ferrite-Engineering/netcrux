// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';

// A wide `case` statement elaborates to one `$pmux` whose select input is
// driven by one comparator per case item. The comparators read the case
// expression, whose nets reach every one of them and so are too wide to route
// ([highFanoutEdgeCap]); each comparator's only routed wire runs to the
// `$pmux`'s select input. The layered layout puts every such cell in the one
// layer before the `$pmux`, so 245 comparators in a RISC-V core's ALU made a
// column 23,000 units tall. No layering option fixes that shape: spreading
// the comparators over more layers leaves a routing slot for every wire that
// passes a later layer, so the last layer stays tall.
//
// Instead the layout engine sees such a bank as one node, sized to hold its
// cells as a grid, with one output port and one wire to the select input.
// After the solve, [expandSelectorBanks] puts every cell back at its place in
// the grid and gives each of their wires a route: out of the cell to the gap
// beside its column, down to the gap below its row, along it to the bank's
// east side, and from there along the wire the engine routed. The wires share
// those last segments the way the bits of a bus share one line. Every cell is
// still drawn, every wire still has a route, and the layout holds the same
// cells and wires it held before.

/// The fewest cells that make a bank: below it, the column the layered
/// layout draws is short enough to read.
const int minSelectorBankSize = 16;

/// The width of every cell a bank holds: the built-in node width.
const int selectorBankCellWidth = 80;

/// The gap beside each column of a bank, which carries the column's wires.
const int selectorBankColumnGap = 30;

/// The gap below each row of a bank, which carries the row's wires.
const int selectorBankRowGap = 20;

/// The size of a port in the layout, as `buildElkInput` makes ports.
const int _portSize = 4;

/// One cell of a [SelectorBank]: its node size and its pins, by face.
@immutable
class SelectorBankCell {
  /// Creates a bank cell.
  const SelectorBankCell({
    required this.id,
    required this.height,
    required this.westPorts,
    required this.eastPorts,
  });

  /// The cell's name, which is its node id.
  final String id;

  /// The node height `buildElkInput` gives the cell.
  final int height;

  /// The ids of the pins on the west face, in `connections` order.
  final List<String> westPorts;

  /// The ids of the pins on the east face, in `connections` order.
  final List<String> eastPorts;

  /// The pins' boxes relative to the node, spread along each face the way
  /// the layout engine spreads `FIXED_SIDE` pins: equal gaps before, between
  /// and after them.
  Map<String, BoundingBox> portBoxes() {
    final boxes = <String, BoundingBox>{};
    void face(List<String> ports, double x) {
      final gap = (height - _portSize * ports.length) / (ports.length + 1);
      for (var i = 0; i < ports.length; i++) {
        boxes[ports[i]] = BoundingBox(
          x: x,
          y: gap * (i + 1) + _portSize * i,
          width: _portSize.toDouble(),
          height: _portSize.toDouble(),
        );
      }
    }

    face(westPorts, -_portSize.toDouble());
    face(eastPorts, selectorBankCellWidth.toDouble());
    return boxes;
  }
}

/// A bank of cells whose only routed wires run to the select input of one
/// `$pmux`, laid out as one node and drawn as a grid (see
/// [findSelectorBanks]).
@immutable
class SelectorBank {
  /// Creates a bank of [cells] feeding [selectPortId] through [wires], each
  /// wire leaving the cell [wireCells] names for its id. The grid is about
  /// as wide as it is tall.
  factory SelectorBank({
    required String selectPortId,
    required List<SelectorBankCell> cells,
    required List<SchematicEdge> wires,
    required Map<String, String> wireCells,
  }) {
    final rowHeight = cells.map((c) => c.height).reduce(math.max);
    const columnPitch = selectorBankCellWidth + selectorBankColumnGap;
    final rowPitch = rowHeight + selectorBankRowGap;
    final square = math.sqrt(cells.length * rowPitch / columnPitch).round();
    final rows = (cells.length / math.max(1, square)).ceil();
    return SelectorBank._(
      selectPortId: selectPortId,
      cells: cells,
      wires: wires,
      wireCells: wireCells,
      rowHeight: rowHeight,
      rows: rows,
      // As many columns as the rows need, so the last is never empty.
      columns: (cells.length / rows).ceil(),
    );
  }

  const SelectorBank._({
    required this.selectPortId,
    required this.cells,
    required this.wires,
    required this.wireCells,
    required this.rowHeight,
    required this.rows,
    required this.columns,
  });

  /// The `$pmux` select pin the bank's wires reach, as `<cell>:S`.
  final String selectPortId;

  /// The bank's cells, in the order of the select bits they drive; the grid
  /// is filled a column at a time, top to bottom.
  final List<SelectorBankCell> cells;

  /// The bank's wires, in the order `buildElkInput` lists edges.
  final List<SchematicEdge> wires;

  /// The cell each of [wires] leaves, by wire id.
  final Map<String, String> wireCells;

  /// The tallest cell's height, which every row takes.
  final int rowHeight;

  /// Rows in the grid.
  final int rows;

  /// Columns in the grid.
  final int columns;

  /// The bank's node id in the layout input.
  String get nodeId => 'bank:$selectPortId';

  /// The bank node's one port, on its east face.
  String get outputPortId => '$nodeId:out';

  /// The one wire the layout engine routes for the bank.
  String get wireId => '$nodeId:wire';

  /// The bank node's width: every column with the gap beside it.
  int get width => columns * (selectorBankCellWidth + selectorBankColumnGap);

  /// The bank node's height: every row with the gap below it.
  int get height => rows * (rowHeight + selectorBankRowGap);

  /// The ELK node that stands for the bank.
  Map<String, Object?> elkNode() => <String, Object?>{
    'id': nodeId,
    'width': width,
    'height': height,
    'ports': <Map<String, Object?>>[
      <String, Object?>{
        'id': outputPortId,
        'width': _portSize,
        'height': _portSize,
        'layoutOptions': const <String, Object?>{'elk.port.side': 'EAST'},
      },
    ],
    'layoutOptions': const <String, Object?>{
      'elk.portConstraints': 'FIXED_SIDE',
    },
  };

  /// The ELK edge that stands for the bank's wires.
  Map<String, Object?> elkEdge() => <String, Object?>{
    'id': wireId,
    'sources': <String>[outputPortId],
    'targets': <String>[selectPortId],
  };
}

/// The banks among [cells]: for each `$pmux` select pin, the cells whose
/// every routed wire in [routed] runs to that pin and which no routed wire
/// enters, when there are at least [minSelectorBankSize] of them.
///
/// [cells] are the cells the layout holds; only those [drawnBuiltIn] accepts
/// (a built-in node, no custom symbol and no supply pins) can join a bank,
/// since the grid places them at the built-in size. A bank cell's other pins
/// are all on nets too wide to route, so nothing but its own wire is lost
/// from the layout engine's view, and that wire is routed by the bank's.
List<SelectorBank> findSelectorBanks(
  Iterable<Cell> cells,
  List<SchematicEdge> routed, {
  required bool Function(Cell cell) drawnBuiltIn,
}) {
  final cellOfPort = <String, Cell>{};
  for (final cell in cells) {
    for (final port in cell.connections.keys) {
      cellOfPort['${cell.name}:$port'] = cell;
    }
  }
  final entered = <String>{};
  final targets = <String, Set<String>>{};
  final wires = <String, List<SchematicEdge>>{};
  for (final edge in routed) {
    final target = cellOfPort[edge.targetPortId];
    if (target != null) entered.add(target.name);
    final source = cellOfPort[edge.sourcePortId];
    if (source == null) continue;
    (targets[source.name] ??= <String>{}).add(edge.targetPortId);
    (wires[source.name] ??= <SchematicEdge>[]).add(edge);
  }

  final membersBySelect = <String, List<Cell>>{};
  for (final cell in cells) {
    if (entered.contains(cell.name)) continue;
    final reached = targets[cell.name];
    if (reached == null || reached.length != 1) continue;
    final select = reached.single;
    final selector = cellOfPort[select];
    if (selector == null ||
        selector.type != r'$pmux' ||
        select != '${selector.name}:S' ||
        identical(selector, cell)) {
      continue;
    }
    if (!drawnBuiltIn(cell)) continue;
    (membersBySelect[select] ??= <Cell>[]).add(cell);
  }

  final banks = <SelectorBank>[];
  for (final entry in membersBySelect.entries) {
    final members = entry.value;
    if (members.length < minSelectorBankSize) continue;
    final selector = cellOfPort[entry.key]!;
    // Each select bit's position, so the grid reads in case-item order.
    final bitIndex = <int, int>{};
    final selectBits = selector.connections['S'] ?? const <BitRef>[];
    for (var i = 0; i < selectBits.length; i++) {
      final bit = selectBits[i];
      if (bit is NetBit) bitIndex.putIfAbsent(bit.netId, () => i);
    }
    int firstBit(Cell cell) => wires[cell.name]!
        .map((w) => bitIndex[w.netId] ?? selectBits.length)
        .reduce(math.min);
    final order = <Cell, int>{
      for (var i = 0; i < members.length; i++) members[i]: i,
    };
    final sorted = List<Cell>.of(members)
      ..sort((a, b) {
        final byBit = firstBit(a).compareTo(firstBit(b));
        return byBit != 0 ? byBit : order[a]!.compareTo(order[b]!);
      });
    final memberNames = {for (final cell in members) cell.name};
    final bankWires = <SchematicEdge>[
      for (final edge in routed)
        if (memberNames.contains(cellOfPort[edge.sourcePortId]?.name)) edge,
    ];
    banks.add(
      SelectorBank(
        selectPortId: entry.key,
        cells: [for (final cell in sorted) _bankCell(cell)],
        wires: bankWires,
        wireCells: {
          for (final edge in bankWires)
            edge.id: cellOfPort[edge.sourcePortId]!.name,
        },
      ),
    );
  }
  return banks;
}

SelectorBankCell _bankCell(Cell cell) {
  final west = <String>[];
  final east = <String>[];
  for (final port in cell.connections.keys) {
    final side = elkPortSideFor(cell.portDirections[port]);
    (side == 'WEST' ? west : east).add('${cell.name}:$port');
  }
  return SelectorBankCell(
    id: cell.name,
    // The built-in node height `buildElkInput` gives a cell: 32 plus 10 per
    // pin on the west and east faces.
    height: 32 + (west.length + east.length) * 10,
    westPorts: west,
    eastPorts: east,
  );
}

/// [layout] with each of [banks] drawn as its cells: every cell placed in the
/// bank's grid with its pins, and every one of the bank's wires routed from
/// its cell's pin along the gaps of the grid to the bank's east side and on
/// along the wire the engine routed for the bank. [layout] itself when
/// [banks] is empty.
///
/// Throws [LayoutException] when the engine's result lacks a bank's node or
/// wire, since the bank's cells would then be missing from the drawing.
NetlistLayout expandSelectorBanks(
  NetlistLayout layout,
  List<SelectorBank> banks,
) {
  if (banks.isEmpty) return layout;
  final byNode = {for (final bank in banks) bank.nodeId: bank};
  final byWire = {for (final bank in banks) bank.wireId: bank};
  final placed = <String, ({NodePosition bank, List<NodePosition> cells})>{};
  final nodes = <NodePosition>[];
  for (final node in layout.nodes) {
    final bank = byNode[node.id];
    if (bank == null) {
      nodes.add(node);
      continue;
    }
    final cells = _placeCells(bank, node.bounds);
    placed[bank.nodeId] = (bank: node, cells: cells);
    nodes.addAll(cells);
  }
  final edges = <EdgeRoute>[];
  final routedBanks = <String>{};
  for (final edge in layout.edges) {
    final bank = byWire[edge.id];
    if (bank == null) {
      edges.add(edge);
      continue;
    }
    final node = placed[bank.nodeId];
    if (node == null) continue;
    routedBanks.add(bank.nodeId);
    edges.addAll(_routeWires(bank, node.bank, node.cells, edge));
  }
  for (final bank in banks) {
    if (!placed.containsKey(bank.nodeId) ||
        !routedBanks.contains(bank.nodeId)) {
      throw LayoutException(
        'the layout engine returned no place for the cells feeding '
        '${bank.selectPortId}',
      );
    }
  }
  return layout.copyWith(nodes: nodes, edges: edges);
}

/// Where the cell at [index] of [bank] sits: its column and row.
(int column, int row) _gridCell(SelectorBank bank, int index) =>
    (index ~/ bank.rows, index % bank.rows);

List<NodePosition> _placeCells(SelectorBank bank, BoundingBox box) {
  const columnPitch = selectorBankCellWidth + selectorBankColumnGap;
  final rowPitch = bank.rowHeight + selectorBankRowGap;
  return <NodePosition>[
    for (var i = 0; i < bank.cells.length; i++)
      () {
        final cell = bank.cells[i];
        final (column, row) = _gridCell(bank, i);
        return NodePosition(
          id: cell.id,
          bounds: BoundingBox(
            x: box.x + column * columnPitch,
            // Centred in the row, which is as tall as the tallest cell.
            y: box.y + row * rowPitch + (bank.rowHeight - cell.height) / 2,
            width: selectorBankCellWidth.toDouble(),
            height: cell.height.toDouble(),
          ),
          ports: cell.portBoxes(),
        );
      }(),
  ];
}

List<EdgeRoute> _routeWires(
  SelectorBank bank,
  NodePosition bankNode,
  List<NodePosition> cells,
  EdgeRoute bankWire,
) {
  final box = bankNode.bounds;
  final rowPitch = bank.rowHeight + selectorBankRowGap;
  // The trunk: the middle of the gap beside the last column.
  final trunkX = box.x + bank.width - selectorBankColumnGap / 2;
  final position = <String, int>{
    for (var i = 0; i < bank.cells.length; i++) bank.cells[i].id: i,
  };
  final cellById = {for (final cell in cells) cell.id: cell};
  final onward = bankWire.points;
  final routes = <EdgeRoute>[];
  for (final wire in bank.wires) {
    final cellId = bank.wireCells[wire.id]!;
    final index = position[cellId]!;
    final node = cellById[cellId]!;
    final pin = node.ports[wire.sourcePortId]!;
    final (_, row) = _gridCell(bank, index);
    final start = LayoutPoint(
      node.bounds.x + pin.x + pin.width,
      node.bounds.y + pin.y + pin.height / 2,
    );
    final columnGapX =
        node.bounds.x + selectorBankCellWidth + selectorBankColumnGap / 2;
    final rowGapY =
        box.y + row * rowPitch + bank.rowHeight + selectorBankRowGap / 2;
    final points = <LayoutPoint>[
      start,
      LayoutPoint(columnGapX, start.y),
      if (columnGapX != trunkX) ...[
        LayoutPoint(columnGapX, rowGapY),
        LayoutPoint(trunkX, rowGapY),
      ],
      if (onward.isNotEmpty) LayoutPoint(trunkX, onward.first.y),
      ...onward,
    ];
    routes.add(
      EdgeRoute(
        id: wire.id,
        points: <LayoutPoint>[
          for (var i = 0; i < points.length; i++)
            if (i == 0 || points[i] != points[i - 1]) points[i],
        ],
      ),
    );
  }
  return routes;
}
