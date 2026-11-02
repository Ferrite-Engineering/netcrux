// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// How a Liberty cell is drawn, from the cell's own description. The cells
// are written the way the SkyWater sky130_fd_sc_hd library writes them
// (pg_pins with pg_type, functions as strings, ff and latch groups), cut
// down to what the drawing reads. Every expected symbol is the gate the
// function means, decided by reading it, not by running the classifier.

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/liberty_cell_symbols.dart';
import 'package:netcrux/services/liberty/liberty_cell_index.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';

/// The supply pins every cell of the library has.
const String _pg = '''
    pg_pin (VGND) { pg_type : "primary_ground" ; voltage_name : "VGND" ; }
    pg_pin (VNB) { pg_type : "pwell" ; voltage_name : "VNB" ; }
    pg_pin (VPB) { pg_type : "nwell" ; voltage_name : "VPB" ; }
    pg_pin (VPWR) { pg_type : "primary_power" ; voltage_name : "VPWR" ; }
''';

/// A combinational cell named [name] with [inputs] and one output [out] of
/// [function].
String _comb(String name, List<String> inputs, String out, String function) =>
    '''
  cell ("$name") {
    area : 3.75 ;
$_pg
${[for (final i in inputs) '    pin ("$i") { direction : "input" ; capacitance : 0.0017 ; }'].join('\n')}
    pin ("$out") {
      direction : "output" ;
      function : "$function" ;
      timing () { related_pin : "${inputs.first}" ; }
    }
  }
''';

String _library(String name) =>
    '''
library ("$name") {
  delay_model : "table_lookup" ;
${_comb('t__inv_1', ['A'], 'Y', '(!A)')}
${_comb('t__buf_1', ['A'], 'X', '(A)')}
${_comb('t__and2_1', ['A', 'B'], 'X', '(A&B)')}
${_comb('t__nand2_1', ['A', 'B'], 'Y', '(!A) | (!B)')}
${_comb('t__or3_1', ['A', 'B', 'C'], 'X', '(A) | (B) | (C)')}
${_comb('t__nor2_1', ['A', 'B'], 'Y', '(!A&!B)')}
${_comb('t__xor2_1', ['A', 'B'], 'X', '(A&!B) | (!A&B)')}
${_comb('t__xnor2_1', ['A', 'B'], 'Y', '(!A&!B) | (A&B)')}
${_comb('t__mux2_1', ['A0', 'A1', 'S'], 'X', '(A0&!S) | (A1&S)')}
${_comb('t__a21oi_1', ['A1', 'A2', 'B1'], 'Y', '(!A1&!B1) | (!A2&!B1)')}
  cell ("t__dfxtp_1") {
    area : 20.0192 ;
$_pg
    ff ("IQ","IQ_N") { clocked_on : "CLK" ; next_state : "D" ; }
    pin ("CLK") { clock : "true" ; direction : "input" ; }
    pin ("D") { direction : "input" ; }
    pin ("Q") { direction : "output" ; function : "IQ" ; }
  }
  cell ("t__dfrbp_1") {
    area : 26.27 ;
$_pg
    ff ("IQ","IQ_N") {
      clear : "!RESET_B" ;
      clocked_on : "CLK" ;
      next_state : "D" ;
    }
    pin ("CLK") { direction : "input" ; }
    pin ("D") { direction : "input" ; }
    pin ("RESET_B") { direction : "input" ; }
    pin ("Q") { direction : "output" ; function : "IQ" ; }
    pin ("Q_N") { direction : "output" ; function : "IQ_N" ; }
  }
  cell ("t__dlxtp_1") {
    area : 15.0144 ;
$_pg
    latch ("IQ","IQ_N") { data_in : "D" ; enable : "GATE" ; }
    pin ("D") { direction : "input" ; }
    pin ("GATE") { clock : "true" ; direction : "input" ; }
    pin ("Q") { direction : "output" ; function : "IQ" ; }
  }
  cell ("t__fa_1") {
    area : 20.0192 ;
$_pg
    pin ("A") { direction : "input" ; }
    pin ("B") { direction : "input" ; }
    pin ("CIN") { direction : "input" ; }
    pin ("COUT") { direction : "output" ; function : "(A&B) | (A&CIN) | (B&CIN)" ; }
    pin ("SUM") { direction : "output" ; function : "(A&!B&!CIN) | (!A&B&!CIN) | (!A&!B&CIN) | (A&B&CIN)" ; }
  }
  cell ("t__conb_1") {
    area : 3.75 ;
$_pg
    pin ("HI") { direction : "output" ; function : "1" ; }
    pin ("LO") { direction : "output" ; function : "0" ; }
  }
  cell ("t__decap_3") {
    area : 3.75 ;
$_pg
  }
  cell ("plain_and") {
    pin (A) { direction : input ; }
    pin (B) { direction : input ; }
    pin (Y) { direction : output ; function : "A B" ; }
  }
  cell ("no_function") {
    pin (A) { direction : input ; }
    pin (Y) { direction : output ; }
  }
}
''';

LibertyLibrary _parse(String name, {String path = 'tt.lib'}) =>
    LibertyParser.parseString(_library(name), path: path);

/// A netlist whose modules are [modules] (name to black-box flag).
NetlistModel _model(Map<String, bool> modules) => NetlistModel.fromJson(
  <String, Object?>{
    'creator': 'test',
    'modules': <String, Object?>{
      for (final entry in modules.entries)
        entry.key: <String, Object?>{
          'attributes': <String, Object?>{
            if (entry.value) 'blackbox': '00000000000000000000000000000001',
          },
          'ports': <String, Object?>{},
          'cells': <String, Object?>{},
          'netnames': <String, Object?>{},
        },
    },
  },
);

void main() {
  final library = _parse('t_tt_025C_1v80');
  LibertyCell cell(String name) =>
      library.cells.firstWhere((c) => c.name == name);

  group('LibertyParser reads the data sheet', () {
    test('the library name, area, functions and supply pin types', () {
      expect(library.name, 't_tt_025C_1v80');
      final nand = cell('t__nand2_1');
      expect(nand.area, 3.75);
      expect(nand.functions, <String, String>{'Y': '(!A) | (!B)'});
      expect(nand.pgPins, <String, String?>{
        'VGND': 'primary_ground',
        'VNB': 'pwell',
        'VPB': 'nwell',
        'VPWR': 'primary_power',
      });
      expect(nand.storage, isNull);
      expect(nand.hasOtherStorage, isFalse);
    });

    test('a flip-flop keeps its ff group and its clock pin', () {
      final dff = cell('t__dfrbp_1');
      final storage = dff.storage!;
      expect(storage.kind, LibertyStorageKind.flipFlop);
      expect(storage.stateNames, <String>['IQ', 'IQ_N']);
      expect(storage.clockedOn, 'CLK');
      expect(storage.nextState, 'D');
      expect(storage.clear, '!RESET_B');
      expect(storage.preset, isNull);
      expect(cell('t__dfxtp_1').clockPins, <String>['CLK']);
    });

    test('everything survives the cache round trip', () {
      final again = LibertyLibrary.fromJson(library.toJson());
      expect(again.toJson(), library.toJson());
      expect(again.name, library.name);
      final dff = again.cells.firstWhere((c) => c.name == 't__dfrbp_1');
      expect(dff.storage!.clear, '!RESET_B');
      expect(dff.area, 26.27);
    });

    test('a bank, a state table or two storage groups are other storage', () {
      final lib = LibertyParser.parseString('''
library (l) {
  cell (BANK) {
    pin (D) { direction : input ; }
    pin (Q) { direction : output ; function : "IQ" ; }
    ff_bank (IQ, IQN, 2) { clocked_on : CK ; next_state : D ; }
  }
  cell (TWO) {
    pin (D) { direction : input ; }
    pin (Q) { direction : output ; function : "IQ" ; }
    ff (IQ, IQN) { clocked_on : CK ; next_state : D ; }
    latch (IL, ILN) { enable : CK ; data_in : D ; }
  }
}
''');
      for (final c in lib.cells) {
        expect(c.hasOtherStorage, isTrue, reason: c.name);
        expect(c.storage, isNull, reason: c.name);
      }
    });
  });

  group('libertyCellSymbolFor', () {
    CellKind kindOf(String name) =>
        libertyCellSymbolFor(cell(name))?.kind ?? CellKind.generic;

    test('each simple gate maps to its symbol', () {
      expect(kindOf('t__inv_1'), CellKind.notGate);
      expect(kindOf('t__buf_1'), CellKind.buffer);
      expect(kindOf('t__and2_1'), CellKind.andGate);
      expect(kindOf('t__nand2_1'), CellKind.nandGate);
      expect(kindOf('t__or3_1'), CellKind.orGate);
      expect(kindOf('t__nor2_1'), CellKind.norGate);
      expect(kindOf('t__xor2_1'), CellKind.xorGate);
      expect(kindOf('t__xnor2_1'), CellKind.xnorGate);
      expect(kindOf('t__mux2_1'), CellKind.mux);
      expect(kindOf('plain_and'), CellKind.andGate);
    });

    test('storage cells map to a flip-flop or a latch', () {
      expect(kindOf('t__dfxtp_1'), CellKind.flipFlop);
      expect(kindOf('t__dfrbp_1'), CellKind.flipFlop);
      expect(kindOf('t__dlxtp_1'), CellKind.latch);
    });

    test('compound, multi-output, constant and undescribed cells keep the '
        'box', () {
      expect(kindOf('t__a21oi_1'), CellKind.generic);
      expect(kindOf('t__fa_1'), CellKind.generic);
      expect(kindOf('t__conb_1'), CellKind.generic);
      expect(kindOf('t__decap_3'), CellKind.generic);
      expect(libertyCellSymbolFor(cell('no_function')), isNull);
    });

    test('power pins go on top and ground pins on the bottom', () {
      final symbol = libertyCellSymbolFor(cell('t__nand2_1'))!;
      expect(symbol.powerPins, <String>{'VPWR', 'VPB'});
      expect(symbol.groundPins, <String>{'VGND', 'VNB'});
      expect(symbol.supplyFace('VPWR'), 'NORTH');
      expect(symbol.supplyFace('VNB'), 'SOUTH');
      expect(symbol.supplyFace('A'), isNull);
      // A box keeps its supply pins placed the same way.
      final aoi = libertyCellSymbolFor(cell('t__a21oi_1'))!;
      expect(aoi.kind, CellKind.generic);
      expect(aoi.hasSupplyPins, isTrue);
    });

    test('a flip-flop marks the pins its clock is: clock : true, or what '
        'clocked_on reads', () {
      expect(libertyCellSymbolFor(cell('t__dfxtp_1'))!.clockPins, <String>{
        'CLK',
      });
      // No `clock : true` here; clocked_on names the pin.
      expect(libertyCellSymbolFor(cell('t__dfrbp_1'))!.clockPins, <String>{
        'CLK',
      });
      // A latch's enable is level-sensitive: no wedge.
      expect(libertyCellSymbolFor(cell('t__dlxtp_1'))!.clockPins, isEmpty);
    });

    test('a tri-state output keeps the box, even when its function reads '
        'every input', () {
      final lib = LibertyParser.parseString('''
library (l) {
  cell (EBUF) {
    pin (A) { direction : input ; }
    pin (TE_B) { direction : input ; }
    pin (Z) { direction : output ; function : "A" ; three_state : "TE_B" ; }
  }
  cell (TBUF_AND) {
    pin (A) { direction : input ; }
    pin (EN) { direction : input ; }
    pin (Z) { direction : output ; function : "A&EN" ; three_state : "!EN" ; }
  }
  cell (TFF) {
    ff (IQ, IQN) { clocked_on : CK ; next_state : D ; }
    pin (CK) { direction : input ; clock : true ; }
    pin (D) { direction : input ; }
    pin (OE) { direction : input ; }
    pin (Q) { direction : output ; function : "IQ" ; three_state : "!OE" ; }
  }
  cell (AND2) {
    pin (A) { direction : input ; }
    pin (EN) { direction : input ; }
    pin (Z) { direction : output ; function : "A&EN" ; }
  }
}
''');
      LibertyCell named(String name) =>
          lib.cells.firstWhere((c) => c.name == name);
      expect(named('TBUF_AND').threeStatePins, <String>['Z']);
      expect(named('AND2').threeStatePins, isEmpty);
      for (final name in const <String>['EBUF', 'TBUF_AND', 'TFF']) {
        expect(libertyCellSymbolFor(named(name)), isNull, reason: name);
      }
      expect(libertyCellSymbolFor(named('AND2'))!.kind, CellKind.andGate);
      final again = LibertyLibrary.fromJson(lib.toJson());
      expect(
        again.cells.firstWhere((c) => c.name == 'TBUF_AND').threeStatePins,
        <String>['Z'],
      );
    });

    test('supply pins without a pg_type are placed by their usual names', () {
      final lib = LibertyParser.parseString('''
library (l) {
  cell (INV) {
    pg_pin (VDD) { }
    pg_pin (VSS) { }
    pg_pin (VAUX) { }
    pin (A) { direction : input ; }
    pin (Y) { direction : output ; function : "!A" ; }
  }
}
''');
      final symbol = libertyCellSymbolFor(lib.cells.single)!;
      expect(symbol.powerPins, <String>{'VDD'});
      expect(symbol.groundPins, <String>{'VSS'});
      expect(symbol.supplyFace('VAUX'), isNull);
    });
  });

  group('LibertyCellIndex', () {
    test('the first library defines a cell, and every library that has it '
        'is listed', () {
      final ss = _parse('t_ss_100C_1v60', path: 'ss.lib');
      final index = LibertyCellIndex(<LibertyLibrary>[library, ss]);
      final record = index['t__nand2_1']!;
      expect(record.library.path, 'tt.lib');
      expect(record.definedIn.map((l) => l.name), <String>[
        't_tt_025C_1v80',
        't_ss_100C_1v60',
      ]);
      expect(index['nothing'], isNull);
    });

    test('a module of the design shadows the library cell of its name, a '
        'black box does not', () {
      final index = LibertyCellIndex(<LibertyLibrary>[library]);
      final model = _model(<String, bool>{
        't__nand2_1': true,
        't__inv_1': false,
      });
      expect(index.forCellType(model, 't__nand2_1'), isNotNull);
      expect(index.forCellType(model, 't__inv_1'), isNull);
      expect(index.forCellType(model, 't__buf_1'), isNotNull);
      final symbols = index.symbolsFor(model);
      expect(symbols['t__nand2_1']?.kind, CellKind.nandGate);
      expect(symbols['t__inv_1'], isNull);
      expect(symbols['no_function'], isNull);
    });

    test('symbols are value-equal, and none without libraries', () {
      final model = _model(const <String, bool>{});
      expect(
        LibertyCellIndex(<LibertyLibrary>[library]).symbolsFor(model),
        LibertyCellIndex(<LibertyLibrary>[_parse('x')]).symbolsFor(model),
      );
      expect(
        LibertyCellIndex.empty.symbolsFor(model),
        LibertyCellSymbols.none,
      );
    });
  });
}
