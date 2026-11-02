// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Two RTL fixtures synthesized to sky130_fd_sc_hd (see PROVENANCE.md beside
// them), opened the two ways a gate-level design reaches the canvas: the
// native gate-level reader on the Verilog with the Liberty library, and the
// Yosys JSON that synthesis wrote, read as File > Open Netlist JSON reads
// it. Both must draw every instance as the gate the independent oracle
// (`test/fixtures/liberty/pdk/liberty_oracle.py`) says its cell is, with the
// same signal pins on the same faces in both layout engines, and the data
// sheet and the area roll-up must agree with the oracle's areas.
//
// The routes differ in one known way. Yosys's `read_liberty -lib` keeps no
// `pg_pin` in a cell's black box, so the synthesized JSON has no supply pins
// at all, while the native reader (like the project's own Yosys route, which
// `native_vs_yosys_test.dart` holds it to) declares every `pg_pin` of the
// library and draws it, unconnected, on the face its type names.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/schematic/symbol_shapes.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/flutter_js_host_vm.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';
import 'package:netcrux/services/liberty/liberty_cell_index.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:netcrux/services/liberty/module_area_rollup.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/schematic/schematic_scope_module.dart';
import 'package:netcrux/services/verilog/native_netlist_reader.dart';
import 'package:netcrux/services/yosys/black_box_port_inference.dart';
import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';

import '../helpers/elk_ffi_library_gate.dart';

const String _dir = 'test/fixtures/gate_level/sky130_fd_sc_hd';
const String _pdk = 'test/fixtures/liberty/pdk/sky130_fd_sc_hd';
const String _libraryPath = '$_pdk/sky130_fd_sc_hd__tt_025C_1v80.lib.gz';
const String _oraclePath =
    '$_pdk/sky130_fd_sc_hd__tt_025C_1v80.expected_symbols.json';

/// The oracle's words for the symbols, as NetCrux's kinds.
const Map<String, CellKind> _kinds = <String, CellKind>{
  'buffer': CellKind.buffer,
  'inverter': CellKind.notGate,
  'and': CellKind.andGate,
  'nand': CellKind.nandGate,
  'or': CellKind.orGate,
  'nor': CellKind.norGate,
  'xor': CellKind.xorGate,
  'xnor': CellKind.xnorGate,
  'mux2': CellKind.mux,
  'dff': CellKind.flipFlop,
  'latch': CellKind.latch,
  'box': CellKind.generic,
};

/// One design opened one way: the model and how its top scope is drawn.
class _Opened {
  _Opened(this.route, this.model, this.index) {
    final root = HierarchyNode.rootOf(model);
    expect(root, isNotNull, reason: '$route has no top module');
    final top = root!;
    final symbols = index.symbolsFor(model);
    graph = SchematicGraphBuilder(liberty: symbols).build(model, top);
    elkInput = buildElkInput(
      schematicScopeModule(model, top.resolve(model)!),
      liberty: symbols,
    );
  }

  final String route;
  final NetlistModel model;
  final LibertyCellIndex index;
  late final SchematicGraph graph;
  late final Map<String, Object?> elkInput;

  String get topName => graph.moduleName;

  /// Instance name to cell type, for every cell of the top module.
  Map<String, String> get types => <String, String>{
    for (final entry in model.modules[topName]!.cells.entries)
      entry.key: entry.value.type,
  };

  /// The library cell of the instance [id].
  LibertyCell libraryCell(String id) =>
      index.forCellType(model, types[id]!)!.cell;

  /// What the canvas is given for each instance, supply pins aside: its
  /// symbol, the pins with a clock wedge, and the face of every signal pin.
  Map<String, String> get drawing => <String, String>{
    for (final cell in graph.cells)
      cell.id: jsonEncode(<String, Object?>{
        'kind': cell.kind.name,
        'clock': <String>[
          for (final p in cell.ports)
            if (p.clock) p.name,
        ]..sort(),
        'sides': <String, String>{
          for (final p in cell.ports)
            if (!libraryCell(cell.id).pgPins.containsKey(p.name))
              p.name: p.side.name,
        },
      }),
  };

  /// The `elk.port.side` of every signal pin of every cell in the ELK input.
  Map<String, Map<String, String?>> get elkSignalSides {
    final cells = <String>{for (final c in graph.cells) c.id};
    return <String, Map<String, String?>>{
      for (final node
          in (elkInput['children']! as List<Object?>)
              .cast<Map<String, Object?>>())
        if (cells.contains(node['id']))
          node['id']! as String: <String, String?>{
            for (final port
                in (node['ports']! as List<Object?>)
                    .cast<Map<String, Object?>>())
              if (!libraryCell(
                node['id']! as String,
              ).pgPins.containsKey((port['id']! as String).split(':').last))
                (port['id']! as String).split(':').last:
                    (port['layoutOptions']
                            as Map<String, Object?>?)?['elk.port.side']
                        as String?,
          },
    };
  }
}

void main() {
  final library = LibertyParser.parseFile(_libraryPath);
  final index = LibertyCellIndex(<LibertyLibrary>[library]);
  final oracle =
      (jsonDecode(File(_oraclePath).readAsStringSync())
              as Map<String, Object?>)['cells']!
          as Map<String, Object?>;
  Map<String, Object?> oracleFor(String type) {
    final entry = oracle[type] as Map<String, Object?>?;
    expect(entry, isNotNull, reason: 'the oracle has no cell $type');
    return entry!;
  }

  List<String> oracleList(String type, String field) =>
      (oracleFor(type)[field]! as List<Object?>).cast<String>();

  /// The face the oracle puts [pin] of [type] on: top for power, bottom for
  /// ground, otherwise right for an output and left for anything else.
  SchematicPortSide expectedFace(String type, LibertyCell cell, String pin) {
    if (oracleList(type, 'power').contains(pin)) return SchematicPortSide.north;
    if (oracleList(type, 'ground').contains(pin)) {
      return SchematicPortSide.south;
    }
    final port = cell.ports.firstWhere((p) => p.name == pin);
    return port.direction == LibertyPortDirection.output
        ? SchematicPortSide.east
        : SchematicPortSide.west;
  }

  _Opened nativeRoute(String design) {
    final outcome = readGateLevelNetlist(
      NativeReadRequest(
        sourceFiles: <String>['$_dir/$design.v'],
        libertyLibraries: <LibertyLibrary>[library],
        topModule: design,
      ),
    );
    expect(
      outcome,
      isA<NativeReadSuccess>(),
      reason: outcome is NativeReadFallbackOutcome
          ? outcome.diagnosticLine
          : '$outcome',
    );
    return _Opened('native', (outcome! as NativeReadSuccess).model, index);
  }

  _Opened jsonRoute(String design) {
    final read = ChunkedYosysJsonReader.parseFile('$_dir/$design.json');
    return _Opened('json', inferBlackBoxPorts(read).model, index);
  }

  for (final design in const <String>['cdc_capture', 'adder4']) {
    group(design, () {
      late _Opened native;
      late _Opened json;
      setUpAll(() {
        native = nativeRoute(design);
        json = jsonRoute(design);
      });

      test('both readers find the same instances of the same cells', () {
        expect(native.topName, design);
        expect(json.topName, design);
        expect(native.types, isNotEmpty);
        expect(json.types, native.types);
      });

      test('every instance is drawn as the oracle says its cell is', () {
        for (final route in <_Opened>[native, json]) {
          final types = route.types;
          for (final cell in route.graph.cells) {
            final type = types[cell.id]!;
            expect(
              cell.kind,
              _kinds[oracleFor(type)['kind']],
              reason: '${route.route}: ${cell.id} ($type)',
            );
            expect(
              <String>[
                for (final p in cell.ports)
                  if (p.clock) p.name,
              ]..sort(),
              oracleList(type, 'clock'),
              reason: '${route.route}: clock pins of ${cell.id}',
            );
          }
        }
      });

      test('both readers draw every instance the same, signal pin by signal '
          'pin', () {
        expect(json.drawing, native.drawing);
      });

      test('the native reader puts every supply pin on the face the oracle '
          'names; the synthesized JSON has none', () {
        for (final cell in native.graph.cells) {
          final type = native.types[cell.id]!;
          final library = native.libraryCell(cell.id);
          final supplies = <String, SchematicPortSide>{
            for (final p in cell.ports)
              if (library.pgPins.containsKey(p.name)) p.name: p.side,
          };
          expect(
            supplies.keys.toSet(),
            <String>{
              ...oracleList(type, 'power'),
              ...oracleList(type, 'ground'),
            },
            reason: cell.id,
          );
          for (final entry in supplies.entries) {
            expect(
              entry.value,
              expectedFace(type, library, entry.key),
              reason: '${cell.id}.${entry.key}',
            );
          }
        }
        for (final cell in json.graph.cells) {
          final library = json.libraryCell(cell.id);
          expect(
            cell.ports.where((p) => library.pgPins.containsKey(p.name)),
            isEmpty,
            reason: cell.id,
          );
        }
      });

      test('the ELK input of both readers puts each signal pin on the side '
          'its library direction names', () {
        expect(json.elkSignalSides, native.elkSignalSides);
        for (final entry in native.elkSignalSides.entries) {
          final cell = native.libraryCell(entry.key);
          for (final pin in entry.value.entries) {
            final port = cell.ports.firstWhere((p) => p.name == pin.key);
            expect(
              pin.value,
              port.direction == LibertyPortDirection.output ? 'EAST' : 'WEST',
              reason: '${entry.key}.${pin.key}',
            );
          }
        }
      });

      void expectFaces(NetlistLayout layout, _Opened route) {
        final types = route.types;
        for (final cell in route.graph.cells) {
          final node = layout.findNode(cell.id);
          expect(node, isNotNull, reason: cell.id);
          final library = route.libraryCell(cell.id);
          for (final entry in node!.ports.entries) {
            final pin = entry.key.split(':').last;
            expect(
              symbolPinFace(entry.value, node.bounds.width, node.bounds.height),
              expectedFace(types[cell.id]!, library, pin),
              reason: '${route.route}: ${entry.key}',
            );
          }
        }
      }

      test('the native engine lays every pin on its face', () {
        if (!requireElkFfiLibrary()) return;
        final solver = NativeElkSolver.open();
        addTearDown(solver.dispose);
        for (final route in <_Opened>[native, json]) {
          final layout = NetlistLayout.fromJson(
            jsonDecode(solver.solve(jsonEncode(route.elkInput)))
                as Map<String, Object?>,
          );
          expectFaces(layout, route);
        }
      });

      // elkjs runs under `flutter test` on JavaScriptCore only; elsewhere the
      // test is not registered rather than skipped (the CI skip guard).
      if (Platform.isMacOS) {
        test('elkjs lays every pin on the same face', () {
          final ElkJsHost host;
          try {
            host = createDefaultElkJsHost();
            initElkRuntime(
              host,
              File('assets/elk/elk.bundled.js').readAsStringSync(),
            );
          } on Object catch (e) {
            markTestSkipped('no JavaScript engine here: $e');
            return;
          }
          addTearDown(host.dispose);
          for (final route in <_Opened>[native, json]) {
            final layout = NetlistLayout.fromJson(
              jsonDecode(runElkLayoutOnHost(host, jsonEncode(route.elkInput)))
                  as Map<String, Object?>,
            );
            expectFaces(layout, route);
          }
        });
      }

      test('the data sheet of one cell of each kind, and the module area, '
          'agree with the oracle', () {
        for (final route in <_Opened>[native, json]) {
          final types = route.types;
          final seenKinds = <CellKind>{};
          var area = 0.0;
          for (final type in types.values) {
            final want = oracleFor(type);
            area += (want['area']! as num).toDouble();
            final record = index.forCellType(route.model, type);
            expect(record, isNotNull, reason: type);
            final kind = record!.symbol?.kind ?? CellKind.generic;
            if (!seenKinds.add(kind)) continue;
            expect(record.cell.name, type);
            expect(record.library.path, _libraryPath);
            expect(record.definedIn, <LibertyLibrary>[library]);
            expect(kind, _kinds[want['kind']], reason: type);
            expect(
              record.cell.area,
              (want['area']! as num).toDouble(),
              reason: type,
            );
            expect(
              _sorted(record.symbol?.powerPins),
              oracleList(type, 'power'),
              reason: type,
            );
            expect(
              _sorted(record.symbol?.groundPins),
              oracleList(type, 'ground'),
              reason: type,
            );
          }
          expect(seenKinds, isNotEmpty);
          final rollup = ModuleAreaRollup(route.model, index).areaOf(design)!;
          expect(rollup.partial, isFalse, reason: route.route);
          expect(rollup.area, closeTo(area, 1e-6), reason: route.route);
        }
      });
    });
  }
}

List<String> _sorted(Set<String>? values) => <String>[...?values]..sort();
