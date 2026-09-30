// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';

void main() {
  group('cellKindFromYosysType', () {
    test(r'$and family → andGate', () {
      expect(cellKindFromYosysType(r'$and'), CellKind.andGate);
      expect(cellKindFromYosysType(r'$reduce_and'), CellKind.andGate);
      expect(cellKindFromYosysType(r'$logic_and'), CellKind.andGate);
    });

    test(r'$or family → orGate', () {
      expect(cellKindFromYosysType(r'$or'), CellKind.orGate);
      expect(cellKindFromYosysType(r'$reduce_or'), CellKind.orGate);
      expect(cellKindFromYosysType(r'$logic_or'), CellKind.orGate);
    });

    test(r'$not → notGate', () {
      expect(cellKindFromYosysType(r'$not'), CellKind.notGate);
      expect(cellKindFromYosysType(r'$reduce_bool'), CellKind.notGate);
    });

    test(r'$mux / $pmux → mux', () {
      expect(cellKindFromYosysType(r'$mux'), CellKind.mux);
      expect(cellKindFromYosysType(r'$pmux'), CellKind.mux);
    });

    test(r'$dff* / $adff* / $sdff* family → flipFlop', () {
      expect(cellKindFromYosysType(r'$dff'), CellKind.flipFlop);
      expect(cellKindFromYosysType(r'$dffe'), CellKind.flipFlop);
      expect(cellKindFromYosysType(r'$adff'), CellKind.flipFlop);
      expect(cellKindFromYosysType(r'$adff_N1N1'), CellKind.flipFlop);
      expect(cellKindFromYosysType(r'$sdff'), CellKind.flipFlop);
      expect(cellKindFromYosysType(r'$dffsr'), CellKind.flipFlop);
    });

    test(r'$dlatch / $adlatch → latch', () {
      expect(cellKindFromYosysType(r'$dlatch'), CellKind.latch);
      expect(cellKindFromYosysType(r'$adlatch'), CellKind.latch);
    });

    test('user-defined module type → generic', () {
      expect(cellKindFromYosysType('cpu'), CellKind.generic);
      expect(cellKindFromYosysType('alu'), CellKind.generic);
    });

    test('unrecognized primitive → generic', () {
      expect(cellKindFromYosysType(r'$add'), CellKind.generic);
      expect(cellKindFromYosysType(r'$eq'), CellKind.generic);
    });
  });

  group('isRegisterCellType', () {
    test('Yosys flop primitives are registers', () {
      expect(isRegisterCellType(r'$dff'), isTrue);
      expect(isRegisterCellType(r'$dffe'), isTrue);
      expect(isRegisterCellType(r'$dffsr'), isTrue);
      expect(isRegisterCellType(r'$adff'), isTrue);
      expect(isRegisterCellType(r'$adff_N1N1'), isTrue);
      expect(isRegisterCellType(r'$sdff'), isTrue);
      expect(isRegisterCellType(r'$sdffce'), isTrue);
    });

    test('user-defined flop suffixes are registers, case-insensitively', () {
      expect(isRegisterCellType('sync_dff'), isTrue);
      expect(isRegisterCellType('meta_ff'), isTrue);
      expect(isRegisterCellType('state_reg'), isTrue);
      expect(isRegisterCellType('SYNC_DFF'), isTrue);
      expect(isRegisterCellType('Meta_FF'), isTrue);
      expect(isRegisterCellType('STATE_REG'), isTrue);
    });

    test('latches are not registers', () {
      expect(isRegisterCellType(r'$dlatch'), isFalse);
      expect(isRegisterCellType(r'$adlatch'), isFalse);
    });

    test('combinational cells and plain modules are not registers', () {
      expect(isRegisterCellType(r'$and'), isFalse);
      expect(isRegisterCellType(r'$mux'), isFalse);
      expect(isRegisterCellType(r'$add'), isFalse);
      expect(isRegisterCellType('cpu'), isFalse);
      expect(isRegisterCellType('register_file'), isFalse);
    });
  });
}
