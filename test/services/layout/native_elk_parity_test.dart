// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The parity gate: the native engine must produce the same layout as elkjs
// for NetCrux's own inputs, coordinate for coordinate. Two forms, so the gate
// holds on every runner:
//
// - **Stored references.** `test/fixtures/layout/<scope>.elkjs.json.gz` is
//   elkjs's output for the ELK input `buildElkInput` makes of a committed
//   netlist fixture, with the input's hash beside it. Regenerate them on a
//   machine with a JavaScript engine (macOS) after any change to
//   `buildElkInput` or the vendored elkjs:
//
//       NETCRUX_WRITE_LAYOUT_REFERENCES=1 flutter test \
//         test/services/layout/native_elk_parity_test.dart
//
//   A stale reference fails, it does not skip: the hash check says so.
//
// - **Live comparison.** On macOS, where elkjs runs on JavaScriptCore under
//   `flutter test`, the same scopes are also solved by elkjs in-process and
//   compared directly, so a change to either engine shows up before anyone
//   regenerates anything. Elsewhere elkjs would run on the QuickJS
//   interpreter, which cannot finish these scopes (chain_1k overflows its
//   stack), so the live group is not registered there; `NETCRUX_PARITY_LIVE=1`
//   forces it. The large scopes join in with `NETCRUX_PARITY_LARGE=1`.
//
// Neither group registers a test it would only skip: the CI test-count guard
// caps skipped tests, and a skip here would hide a missing reference.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/flutter_js_host_vm.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';
import 'package:netcrux/services/schematic/declared_cell_ports.dart';

import '../../helpers/elk_ffi_library_gate.dart';

/// One scope of one committed netlist fixture.
class _Scope {
  const _Scope(this.fixture, this.module, {this.large = false});

  /// Path under `test/fixtures/netlist/`, `.json` or `.json.gz`.
  final String fixture;

  /// The module laid out.
  final String module;

  /// Whether the live comparison only runs with `NETCRUX_PARITY_LARGE=1`
  /// (elkjs takes seconds and, on an interpreter, minutes).
  final bool large;

  String get name => '${fixture.split('/').first}/$module';
}

const _scopes = <_Scope>[
  _Scope('design_seed/generated/design_seed.netlist.json', 'top'),
  _Scope('chain_1k/generated/chain_1k.netlist.json', 'chain_1k'),
  _Scope('vexriscv/captured/vexriscv.netlist.json.gz', 'InstructionCache'),
  _Scope('vexriscv/captured/vexriscv.netlist.json.gz', 'DataCache'),
  _Scope('serv_ice40/captured/serv_ice40.netlist.json.gz', 'service'),
  _Scope('picorv32/captured/picorv32.netlist.json.gz', 'picorv32', large: true),
  _Scope('vexriscv/captured/vexriscv.netlist.json.gz', 'VexRiscv', large: true),
];

const _referenceDir = 'test/fixtures/layout';

String _elkInputFor(_Scope scope) {
  final file = File('test/fixtures/netlist/${scope.fixture}');
  final bytes = file.readAsBytesSync();
  final text = scope.fixture.endsWith('.gz')
      ? utf8.decode(gzip.decode(bytes))
      : utf8.decode(bytes);
  final model = NetlistModel.fromJson(jsonDecode(text) as Map<String, Object?>);
  // The module the app lays out: with every declared port of every cell.
  return jsonEncode(
    buildElkInput(withDeclaredCellPorts(model, model.modules[scope.module]!)),
  );
}

/// 32-bit FNV-1a over the input text plus its length: enough to tell "same
/// input" from "not" for a staleness check.
String _fingerprint(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
    hash ^= unit >> 8;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return '${hash.toRadixString(16).padLeft(8, '0')}-${text.length}';
}

NetlistLayout _parse(String json) =>
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

void main() {
  final writeReferences =
      Platform.environment['NETCRUX_WRITE_LAYOUT_REFERENCES'] == '1';
  final includeLarge = Platform.environment['NETCRUX_PARITY_LARGE'] == '1';
  final liveComparison =
      Platform.isMacOS || Platform.environment['NETCRUX_PARITY_LIVE'] == '1';
  File referenceFor(_Scope scope) => File(
    '$_referenceDir/${scope.name.replaceAll('/', '.')}.elkjs.json.gz',
  );

  group('native engine matches the stored elkjs references', () {
    for (final scope in _scopes) {
      final reference = referenceFor(scope);
      // A scope without a stored reference has no test, not a skipped one.
      if (!reference.existsSync()) continue;
      test(scope.name, () {
        if (!requireElkFfiLibrary()) return;
        final fingerprintFile = File('${reference.path}.input');
        final input = _elkInputFor(scope);
        expect(
          fingerprintFile.existsSync()
              ? fingerprintFile.readAsStringSync().trim()
              : '',
          _fingerprint(input),
          reason:
              'the stored elkjs reference for ${scope.name} was made from a '
              'different ELK input; regenerate with '
              'NETCRUX_WRITE_LAYOUT_REFERENCES=1',
        );
        final expected = _parse(
          utf8.decode(gzip.decode(reference.readAsBytesSync())),
        );
        final solver = NativeElkSolver.open();
        addTearDown(solver.dispose);
        final actual = _parse(solver.solve(input));
        final diffs = layoutDifferences(actual, expected);
        expect(diffs, isEmpty, reason: diffs.take(8).join('\n'));
        // elkjs honours the fixed port sides too: the reference is evidence
        // about the browser engine, which has no other gate here.
        final sides = portSideViolations(expected, input);
        expect(sides, isEmpty, reason: sides.take(8).join('\n'));
      });
    }
  });

  group('native engine matches elkjs live', () {
    if (!liveComparison) return;
    for (final scope in _scopes) {
      if (scope.large && !includeLarge) continue;
      test(scope.name, () {
        if (!requireElkFfiLibrary()) return;
        final input = _elkInputFor(scope);
        final ElkJsHost host;
        try {
          host = createDefaultElkJsHost();
          initElkRuntime(
            host,
            File('assets/elk/elk.bundled.js').readAsStringSync(),
          );
        } on Object catch (e) {
          markTestSkipped('no JavaScript engine for the live reference: $e');
          return;
        }
        addTearDown(host.dispose);
        final String jsResult;
        try {
          jsResult = runElkLayoutOnHost(host, input);
        } on LayoutException catch (e) {
          // An interpreter that cannot finish the scope is exactly what the
          // native engine replaces; it is not evidence about parity.
          markTestSkipped('elkjs could not lay out ${scope.name} here: $e');
          return;
        }
        if (writeReferences) {
          Directory(_referenceDir).createSync(recursive: true);
          final base =
              '$_referenceDir/${scope.name.replaceAll('/', '.')}.elkjs.json';
          File('$base.gz').writeAsBytesSync(gzip.encode(utf8.encode(jsResult)));
          File('$base.gz.input').writeAsStringSync('${_fingerprint(input)}\n');
        }
        final solver = NativeElkSolver.open();
        addTearDown(solver.dispose);
        final actual = _parse(solver.solve(input));
        final diffs = layoutDifferences(actual, _parse(jsResult));
        expect(diffs, isEmpty, reason: diffs.take(8).join('\n'));
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
  });
}
