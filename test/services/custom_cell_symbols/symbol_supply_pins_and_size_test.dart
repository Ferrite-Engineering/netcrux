// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/port_anchor.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/liberty_cell_symbols.dart';
import 'package:netcrux/services/custom_cell_symbols/symbol_supply_pins.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/schematic/schematic_scope_module.dart';

CustomCellSymbol _symbol({
  String type = 'pwr_cell',
  Set<String> power = const <String>{},
  Set<String> ground = const <String>{},
  double? layoutWidth,
  double? layoutHeight,
}) => CustomCellSymbol(
  id: 'id-$type',
  moduleType: type,
  kind: CustomCellSymbolKind.svg,
  content: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 80"/>',
  width: 100,
  height: 80,
  portAnchors: const <String, PortAnchor>{
    'A': PortAnchor(x: 0, y: 0.5, side: PortAnchorSide.left),
    'Y': PortAnchor(x: 1, y: 0.5, side: PortAnchorSide.right),
    'VDD': PortAnchor(x: 0.5, y: 0, side: PortAnchorSide.top),
    'VSS': PortAnchor(x: 0.5, y: 1, side: PortAnchorSide.bottom),
  },
  createdAt: '',
  updatedAt: '',
  powerPins: power,
  groundPins: ground,
  layoutWidth: layoutWidth,
  layoutHeight: layoutHeight,
);

/// A top module with one `pwr_cell` instance whose supply pins are declared
/// by the cell's module and left unconnected, or wired when [wired].
NetlistModel _design({required bool wired}) {
  final json = _designJson(wired: wired);
  return NetlistModel.fromJson(json);
}

Map<String, Object?> _designJson({required bool wired}) => <String, Object?>{
  'modules': <String, Object?>{
    'pwr_cell': <String, Object?>{
      'attributes': <String, Object?>{
        'blackbox': '00000000000000000000000000000001',
      },
      'ports': <String, Object?>{
        'A': <String, Object?>{
          'direction': 'input',
          'bits': <int>[2],
        },
        'Y': <String, Object?>{
          'direction': 'output',
          'bits': <int>[3],
        },
        'VDD': <String, Object?>{
          'direction': 'inout',
          'bits': <int>[4],
        },
        'VSS': <String, Object?>{
          'direction': 'inout',
          'bits': <int>[5],
        },
      },
      'cells': <String, Object?>{},
      'netnames': <String, Object?>{},
    },
    'top': <String, Object?>{
      'attributes': <String, Object?>{
        'top': '00000000000000000000000000000001',
      },
      'ports': <String, Object?>{
        'a': <String, Object?>{
          'direction': 'input',
          'bits': <int>[2],
        },
        'y': <String, Object?>{
          'direction': 'output',
          'bits': <int>[3],
        },
        if (wired)
          'vdd': <String, Object?>{
            'direction': 'input',
            'bits': <int>[4],
          },
      },
      'cells': <String, Object?>{
        'u1': <String, Object?>{
          'type': 'pwr_cell',
          'port_directions': <String, Object?>{
            'A': 'input',
            'Y': 'output',
            if (wired) 'VDD': 'inout',
          },
          'connections': <String, Object?>{
            'A': <int>[2],
            'Y': <int>[3],
            if (wired) 'VDD': <int>[4],
          },
        },
      },
      'netnames': <String, Object?>{},
    },
  },
};

void main() {
  group('CustomCellSymbol supply pins and requested size', () {
    test('round-trip through JSON and take part in equality', () {
      final symbol = _symbol(
        power: const <String>{'VDD'},
        ground: const <String>{'VSS'},
        layoutWidth: 50,
        layoutHeight: 40,
      );
      final json = symbol.toJson();
      expect(json['powerPins'], <String>['VDD']);
      expect(json['groundPins'], <String>['VSS']);
      expect(json['layoutWidth'], 50);
      expect(json['layoutHeight'], 40);
      expect(CustomCellSymbol.fromJson(json), symbol);
      expect(symbol, isNot(_symbol()));
    });

    test('are left out of the JSON of a symbol without them, and a symbol '
        'saved before they existed reads with none', () {
      final json = _symbol().toJson();
      expect(json.containsKey('powerPins'), isFalse);
      expect(json.containsKey('layoutWidth'), isFalse);
      final read = CustomCellSymbol.fromJson(json);
      expect(read.powerPins, isEmpty);
      expect(read.groundPins, isEmpty);
      expect(read.layoutWidth, isNull);
      expect(read.layoutHeight, isNull);
    });

    test('a malformed size or pin list is ignored, not thrown on', () {
      final json = <String, Object?>{
        ..._symbol().toJson(),
        'powerPins': 'VDD',
        'groundPins': <Object?>['VSS', 7],
        'layoutWidth': -3,
        'layoutHeight': 'tall',
      };
      final read = CustomCellSymbol.fromJson(json);
      expect(read.powerPins, isEmpty);
      expect(read.groundPins, <String>{'VSS'});
      expect(read.layoutWidth, isNull);
      expect(read.layoutHeight, isNull);
    });
  });

  group('a requested size enlarges the node, never shrinks it', () {
    test('the geometry carries the larger of the two asks at the aspect', () {
      final geometry = CellSymbolGeometry.fromSymbol(
        _symbol(layoutWidth: 200, layoutHeight: 100),
      );
      expect(geometry.aspect, 1.25);
      // 200 wide at 1.25 is 160 tall, more than the 100 asked for.
      expect(geometry.requestedHeight, 160);
      expect(CellSymbolGeometry.fromSymbol(_symbol()).requestedHeight, isNull);
    });

    test('the node size takes the request when it is larger', () {
      const faces = <String>['WEST', 'EAST', 'NORTH', 'SOUTH'];
      final byPins = symbolCellNodeSize(faces, 1.25);
      expect(byPins, (width: 52.5, height: 42.0));
      expect(
        symbolCellNodeSize(faces, 1.25, requestedHeight: 30),
        byPins,
        reason: 'a request below what the pins need changes nothing',
      );
      expect(
        symbolCellNodeSize(faces, 1.25, requestedHeight: 80),
        (width: 100.0, height: 80.0),
      );
    });

    test('a very large request is capped', () {
      final geometry = CellSymbolGeometry.fromSymbol(
        _symbol(layoutHeight: 1000000000),
      );
      expect(geometry.requestedHeight, CellSymbolGeometry.maxRequestedHeight);
    });
  });

  group('withSymbolSupplyPins', () {
    test('adds the named pins for a type with no Liberty description', () {
      final merged = withSymbolSupplyPins(LibertyCellSymbols.none, {
        'pwr_cell': _symbol(
          power: const <String>{'VDD'},
          ground: const <String>{'VSS'},
        ),
      });
      final entry = merged['pwr_cell']!;
      expect(entry.kind, CellKind.generic);
      expect(entry.powerPins, <String>{'VDD'});
      expect(entry.groundPins, <String>{'VSS'});
    });

    test('keeps a Liberty description that declares supply pins', () {
      const liberty = LibertyCellSymbols(<String, LibertyCellSymbol>{
        'pwr_cell': LibertyCellSymbol(
          kind: CellKind.notGate,
          powerPins: <String>{'VPWR'},
          groundPins: <String>{'VGND'},
        ),
      });
      final merged = withSymbolSupplyPins(liberty, {
        'pwr_cell': _symbol(power: const <String>{'VDD'}),
      });
      expect(identical(merged, liberty), isTrue);
    });

    test('adds supply pins to a Liberty description that has none, keeping '
        'its symbol and clock pins', () {
      const liberty = LibertyCellSymbols(<String, LibertyCellSymbol>{
        'pwr_cell': LibertyCellSymbol(
          kind: CellKind.flipFlop,
          clockPins: <String>{'CK'},
        ),
      });
      final entry = withSymbolSupplyPins(liberty, {
        'pwr_cell': _symbol(ground: const <String>{'VSS'}),
      })['pwr_cell']!;
      expect(entry.kind, CellKind.flipFlop);
      expect(entry.clockPins, <String>{'CK'});
      expect(entry.groundPins, <String>{'VSS'});
    });

    test('returns its input when no symbol names a supply pin', () {
      const liberty = LibertyCellSymbols.none;
      expect(
        identical(
          withSymbolSupplyPins(liberty, {'pwr_cell': _symbol()}),
          liberty,
        ),
        isTrue,
      );
    });
  });

  group('the supply rule holds for pins a symbol names', () {
    final symbols = <String, CustomCellSymbol>{
      'pwr_cell': _symbol(
        power: const <String>{'VDD'},
        ground: const <String>{'VSS'},
      ),
    };
    final liberty = withSymbolSupplyPins(LibertyCellSymbols.none, symbols);

    test('a scope that wires no supply hides them', () {
      final model = _design(wired: false);
      final top = model.modules['top']!;
      final shown = schematicScopeModule(model, top, liberty: liberty);
      expect(shown.cells['u1']!.connections.keys, <String>['A', 'Y']);
    });

    test('a scope that wires one shows them all', () {
      final model = _design(wired: true);
      final top = model.modules['top']!;
      final shown = schematicScopeModule(model, top, liberty: liberty);
      expect(
        shown.cells['u1']!.connections.keys.toSet(),
        <String>{'A', 'Y', 'VDD', 'VSS'},
      );
      // And the layout puts them on the faces the symbol anchors them to.
      final input = buildElkInput(
        shown,
        symbols: CellSymbolGeometries.fromSnapshot(symbols),
        liberty: liberty,
      );
      final node = (input['children']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere((n) => n['id'] == 'u1');
      final sides = <String, Object?>{
        for (final port
            in (node['ports']! as List<Object?>).cast<Map<String, Object?>>())
          (port['id']! as String).split(':').last:
              (port['layoutOptions']! as Map<String, Object?>)['elk.port.side'],
      };
      expect(sides, <String, Object?>{
        'A': 'WEST',
        'Y': 'EAST',
        'VDD': 'NORTH',
        'VSS': 'SOUTH',
      });
    });
  });
}
