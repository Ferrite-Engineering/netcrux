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
// library. Neither draws one: a scope that connects no supply pin draws none
// of the unconnected ones. A hand-written powered netlist
// (`test/fixtures/gate_level/sky130_fd_sc_hd_powered/`) connects them, and
// there every supply pin is drawn, the one it leaves unconnected included, on
// the face its type names.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
// The netlist shims each re-export the whole model, `Cell` included.
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
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
      schematicScopeModule(model, top.resolve(model)!, liberty: symbols),
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

  /// The `elk.port.side` of every pin of every cell in the ELK input, supply
  /// pins included.
  Map<String, Map<String, String?>> get elkSides {
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
              (port['id']! as String).split(':').last:
                  (port['layoutOptions']
                          as Map<String, Object?>?)?['elk.port.side']
                      as String?,
          },
    };
  }

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

      test('a synthesized netlist connects no supply pin, so neither reader '
          'draws or lays out one, and every signal pin stays', () {
        // The native reader declares every pg_pin; the rule takes them away.
        final declared = native.model.modules[design]!.cells.values.first;
        expect(
          native.model.modules[declared.type]!.ports.keys,
          containsAll(<String>['VPWR', 'VGND', 'VPB', 'VNB']),
        );
        for (final route in <_Opened>[native, json]) {
          for (final cell in route.graph.cells) {
            final library = route.libraryCell(cell.id);
            expect(
              cell.ports.where((p) => library.pgPins.containsKey(p.name)),
              isEmpty,
              reason: '${route.route}: ${cell.id}',
            );
            expect(
              <String>{for (final p in cell.ports) p.name},
              <String>{
                for (final port in library.ports)
                  if (!library.pgPins.containsKey(port.name)) port.name,
              },
              reason: '${route.route}: signal pins of ${cell.id}',
            );
            expect(
              route.elkSides[cell.id]!.keys.toSet(),
              <String>{for (final p in cell.ports) p.name},
              reason: '${route.route}: ELK ports of ${cell.id}',
            );
          }
        }
        expect(json.elkSides, native.elkSides);
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

  group('powered (supplies wired, one left unconnected)', () {
    late _Opened powered;
    setUpAll(() {
      final outcome = readGateLevelNetlist(
        NativeReadRequest(
          sourceFiles: const <String>[
            'test/fixtures/gate_level/sky130_fd_sc_hd_powered/powered.v',
          ],
          libertyLibraries: <LibertyLibrary>[library],
          topModule: 'powered',
        ),
      );
      expect(outcome, isA<NativeReadSuccess>());
      powered = _Opened(
        'powered',
        (outcome! as NativeReadSuccess).model,
        index,
      );
    });

    // From the netlist text: each instance's supply connections.
    const supplies = <String>{'VPWR', 'VGND', 'VPB', 'VNB'};
    const unconnected = <String, Set<String>>{
      'u_nand': <String>{},
      'u_aoi': <String>{'VNB'},
      'u_ff': <String>{},
    };

    test('every supply pin is drawn on the face its type names, the '
        'unconnected one included', () {
      expect(
        <String>{for (final c in powered.graph.cells) c.id},
        unconnected.keys.toSet(),
      );
      for (final cell in powered.graph.cells) {
        final type = powered.types[cell.id]!;
        final library = powered.libraryCell(cell.id);
        final drawn = <String, SchematicPort>{
          for (final p in cell.ports)
            if (library.pgPins.containsKey(p.name)) p.name: p,
        };
        expect(drawn.keys.toSet(), supplies, reason: cell.id);
        for (final entry in drawn.entries) {
          expect(
            entry.value.side,
            expectedFace(type, library, entry.key),
            reason: '${cell.id}.${entry.key}',
          );
          expect(
            entry.value.tie == PinTie.unconnected,
            unconnected[cell.id]!.contains(entry.key),
            reason: '${cell.id}.${entry.key} is ${entry.value.tie}',
          );
        }
        expect(
          powered.elkSides[cell.id],
          containsPair('VNB', 'SOUTH'),
          reason: cell.id,
        );
        expect(
          powered.elkSides[cell.id],
          containsPair('VPWR', 'NORTH'),
          reason: cell.id,
        );
      }
    });

    void expectSupplyFaces(NetlistLayout layout) {
      for (final cell in powered.graph.cells) {
        final node = layout.findNode(cell.id);
        expect(node, isNotNull, reason: cell.id);
        final library = powered.libraryCell(cell.id);
        final laid = <String>{};
        for (final entry in node!.ports.entries) {
          final pin = entry.key.split(':').last;
          laid.add(pin);
          expect(
            symbolPinFace(entry.value, node.bounds.width, node.bounds.height),
            expectedFace(powered.types[cell.id]!, library, pin),
            reason: entry.key,
          );
        }
        expect(laid, containsAll(supplies), reason: cell.id);
      }
    }

    test('the native engine lays every supply pin on its face', () {
      if (!requireElkFfiLibrary()) return;
      final solver = NativeElkSolver.open();
      addTearDown(solver.dispose);
      expectSupplyFaces(
        NetlistLayout.fromJson(
          jsonDecode(solver.solve(jsonEncode(powered.elkInput)))
              as Map<String, Object?>,
        ),
      );
    });

    if (Platform.isMacOS) {
      test('elkjs lays every supply pin on the same face', () {
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
        expectSupplyFaces(
          NetlistLayout.fromJson(
            jsonDecode(runElkLayoutOnHost(host, jsonEncode(powered.elkInput)))
                as Map<String, Object?>,
          ),
        );
      });
    }

    test('removing the one supply connection of a one-cell scope hides its '
        'unconnected supply pins again', () {
      final model = powered.model;
      final top = model.modules['powered']!;
      final symbols = index.symbolsFor(model);
      expect(scopeConnectsSupplyPins(top, symbols), isTrue);
      final aoi = top.cells['u_aoi']!;
      final bare = top.copyWith(
        cells: <String, Cell>{
          'u_aoi': aoi.copyWith(
            connections: <String, List<BitRef>>{
              for (final e in aoi.connections.entries)
                if (!supplies.contains(e.key)) e.key: e.value,
            },
          ),
        },
      );
      expect(scopeConnectsSupplyPins(bare, symbols), isFalse);
      final drawn = schematicScopeModule(model, bare, liberty: symbols);
      expect(drawn.cells['u_aoi']!.connections.keys.toSet(), <String>{
        'A1',
        'A2',
        'B1',
        'Y',
      });
      // Without the libraries nothing is taken away.
      expect(
        schematicScopeModule(model, bare).cells['u_aoi']!.connections.keys,
        containsAll(supplies),
      );
    });
  });
}

List<String> _sorted(Set<String>? values) => <String>[...?values]..sort();
