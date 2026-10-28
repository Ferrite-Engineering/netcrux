// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The parity gate's shared parts, free of `dart:io` so the desktop gate
// (`test/services/layout/native_elk_parity_test.dart`) and the browser gate
// (`test/services/layout/elk_wasm_web_test.dart`) compare engines against the
// same stored elkjs references the same way.

import 'dart:convert';

import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/schematic/schematic_scope_module.dart';

/// One scope of one committed netlist fixture.
class LayoutParityScope {
  const LayoutParityScope(this.fixture, this.module, {this.large = false});

  /// Path under `test/fixtures/netlist/`, `.json` or `.json.gz`.
  final String fixture;

  /// The module laid out.
  final String module;

  /// Whether the live comparison only runs with `NETCRUX_PARITY_LARGE=1`
  /// (elkjs takes seconds and, on an interpreter, minutes).
  final bool large;

  String get name => '${fixture.split('/').first}/$module';

  /// The stored elkjs reference, relative to `test/`.
  String get referencePath =>
      'fixtures/layout/${name.replaceAll('/', '.')}.elkjs.json.gz';
}

const layoutParityScopes = <LayoutParityScope>[
  LayoutParityScope('design_seed/generated/design_seed.netlist.json', 'top'),
  LayoutParityScope('chain_1k/generated/chain_1k.netlist.json', 'chain_1k'),
  LayoutParityScope(
    'vexriscv/captured/vexriscv.netlist.json.gz',
    'InstructionCache',
  ),
  LayoutParityScope('vexriscv/captured/vexriscv.netlist.json.gz', 'DataCache'),
  LayoutParityScope(
    'serv_ice40/captured/serv_ice40.netlist.json.gz',
    'service',
  ),
  LayoutParityScope(
    'picorv32/captured/picorv32.netlist.json.gz',
    'picorv32',
    large: true,
  ),
  LayoutParityScope(
    'vexriscv/captured/vexriscv.netlist.json.gz',
    'VexRiscv',
    large: true,
  ),
];

/// The ELK input the app builds for [module] of the netlist [netlistJson]:
/// the module the schematic draws ([schematicScopeModule]).
String elkInputForModule(String netlistJson, String module) {
  final model = NetlistModel.fromJson(
    jsonDecode(netlistJson) as Map<String, Object?>,
  );
  return jsonEncode(
    buildElkInput(schematicScopeModule(model, model.modules[module]!)),
  );
}

/// 32-bit FNV-1a over the input text plus its length: enough to tell "same
/// input" from "not" for a staleness check.
String layoutInputFingerprint(String text) {
  // hash * 0x01000193 mod 2^32, split as hash * 2^24 + hash * 0x193 so no
  // intermediate passes 2^53: a browser's ints are doubles.
  int times(int hash) => (((hash & 0xff) << 24) + hash * 0x193) & 0xffffffff;
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = times(hash ^ (unit & 0xff));
    hash = times(hash ^ (unit >> 8));
  }
  return '${hash.toRadixString(16).padLeft(8, '0')}-${text.length}';
}

NetlistLayout parseLayout(String json) =>
    NetlistLayout.fromJson(jsonDecode(json) as Map<String, Object?>);

/// Every coordinate that differs by more than [tolerance], described.
List<String> layoutDifferences(
  NetlistLayout actual,
  NetlistLayout expected, {
  double tolerance = 1e-6,
}) {
  final diffs = <String>[];
  bool near(double a, double b) => (a - b).abs() <= tolerance;
  void box(String what, BoundingBox a, BoundingBox b) {
    if (!near(a.x, b.x) ||
        !near(a.y, b.y) ||
        !near(a.width, b.width) ||
        !near(a.height, b.height)) {
      diffs.add('$what: $a vs $b');
    }
  }

  box('root bounds', actual.bounds, expected.bounds);
  if (actual.nodes.length != expected.nodes.length) {
    diffs.add('${actual.nodes.length} nodes vs ${expected.nodes.length}');
  }
  final expectedNodes = <String, NodePosition>{
    for (final node in expected.nodes) node.id: node,
  };
  for (final node in actual.nodes) {
    final other = expectedNodes[node.id];
    if (other == null) {
      diffs.add('node ${node.id} only in actual');
      continue;
    }
    box('node ${node.id}', node.bounds, other.bounds);
    for (final port in node.ports.entries) {
      final match = other.ports[port.key];
      if (match == null) {
        diffs.add('port ${node.id}/${port.key} only in actual');
      } else {
        box('port ${node.id}/${port.key}', port.value, match);
      }
    }
  }
  if (actual.edges.length != expected.edges.length) {
    diffs.add('${actual.edges.length} edges vs ${expected.edges.length}');
  }
  final expectedEdges = <String, EdgeRoute>{
    for (final edge in expected.edges) edge.id: edge,
  };
  for (final edge in actual.edges) {
    final other = expectedEdges[edge.id];
    if (other == null) {
      diffs.add('edge ${edge.id} only in actual');
      continue;
    }
    final points = other.points;
    if (points.length != edge.points.length) {
      diffs.add(
        'edge ${edge.id}: ${edge.points.length} points vs ${points.length}',
      );
      continue;
    }
    for (var i = 0; i < points.length; i++) {
      final a = edge.points[i];
      final b = points[i];
      if (!near(a.x, b.x) || !near(a.y, b.y)) {
        diffs.add('edge ${edge.id}[$i]: (${a.x}, ${a.y}) vs (${b.x}, ${b.y})');
      }
    }
  }
  return diffs;
}

/// Every cell port of [layout] that is not on the face [inputJson] fixes for
/// it, described: a `WEST` port must sit on the left half of its node, an
/// `EAST` port on the right half.
List<String> portSideViolations(NetlistLayout layout, String inputJson) {
  final violations = <String>[];
  final input = jsonDecode(inputJson) as Map<String, Object?>;
  for (final child
      in (input['children']! as List<Object?>).cast<Map<String, Object?>>()) {
    final ports = child['ports'] as List<Object?>?;
    if (ports == null) continue;
    final node = layout.findNode(child['id']! as String);
    if (node == null) continue;
    for (final port in ports.cast<Map<String, Object?>>()) {
      final id = port['id']! as String;
      final side =
          (port['layoutOptions'] as Map<String, Object?>?)?['elk.port.side'];
      final box = node.ports[id];
      if (box == null) continue;
      final centre = box.x + box.width / 2;
      final west = centre < node.bounds.width / 2;
      if ((side == 'WEST') != west) {
        violations.add('$id fixed $side, placed at x=${box.x}');
      }
    }
  }
  return violations;
}
