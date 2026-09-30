// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/services/search/design_search_service.dart';

NetlistModel _modelWith({
  required Map<String, Cell> topCells,
  required Map<String, Net> topNets,
}) {
  return NetlistModel(
    creator: 'test',
    modules: <String, Module>{
      'top': Module(
        name: 'top',
        attributes: const <String, String>{'top': '1'},
        ports: const {},
        cells: topCells,
        nets: topNets,
      ),
    },
  );
}

void main() {
  group('DesignSearchService', () {
    const service = DesignSearchService();

    test('empty query returns empty list', () {
      final model = _modelWith(
        topCells: const <String, Cell>{},
        topNets: const <String, Net>{},
      );
      expect(service.search(model: model, query: ''), isEmpty);
      expect(service.search(model: model, query: '   '), isEmpty);
    });

    test('substring match against cell names', () {
      final model = _modelWith(
        topCells: const <String, Cell>{
          'alu_adder': Cell(
            name: 'alu_adder',
            type: r'$add',
            parameters: <String, String>{},
            attributes: <String, String>{},
            portDirections: <String, PortDirection>{},
            connections: <String, List<BitRef>>{},
          ),
        },
        topNets: const <String, Net>{},
      );
      final hits = service.search(model: model, query: 'adder');
      expect(hits, hasLength(1));
      expect(hits.first.name, 'alu_adder');
      expect(hits.first.kind, SearchResultKind.cell);
    });

    test('glob match', () {
      final model = _modelWith(
        topCells: const <String, Cell>{
          'alu_a': Cell(
            name: 'alu_a',
            type: r'$add',
            parameters: <String, String>{},
            attributes: <String, String>{},
            portDirections: <String, PortDirection>{},
            connections: <String, List<BitRef>>{},
          ),
          'alu_b': Cell(
            name: 'alu_b',
            type: r'$add',
            parameters: <String, String>{},
            attributes: <String, String>{},
            portDirections: <String, PortDirection>{},
            connections: <String, List<BitRef>>{},
          ),
        },
        topNets: const <String, Net>{},
      );
      final hits = service.search(
        model: model,
        query: 'alu_?',
        mode: SearchMode.glob,
      );
      expect(hits, hasLength(2));
    });

    test('regex match', () {
      final model = _modelWith(
        topCells: const <String, Cell>{},
        topNets: const <String, Net>{
          'data_in': Net(
            name: 'data_in',
            bits: [],
            attributes: <String, String>{},
          ),
          'data_out': Net(
            name: 'data_out',
            bits: [],
            attributes: <String, String>{},
          ),
        },
      );
      final hits = service.search(
        model: model,
        query: r'^data_in$',
        mode: SearchMode.regex,
      );
      expect(hits, hasLength(1));
      expect(hits.first.kind, SearchResultKind.net);
      expect(hits.first.name, 'data_in');
    });

    test('invalid regex returns empty', () {
      final model = _modelWith(
        topCells: const <String, Cell>{},
        topNets: const <String, Net>{},
      );
      // Unmatched [ — should not throw, should produce no hits.
      final hits = service.search(
        model: model,
        query: '[',
        mode: SearchMode.regex,
      );
      expect(hits, isEmpty);
    });

    test('maxResults caps the list', () {
      final cells = <String, Cell>{
        for (var i = 0; i < 50; i++)
          'cell_$i': Cell(
            name: 'cell_$i',
            type: r'$add',
            parameters: const <String, String>{},
            attributes: const <String, String>{},
            portDirections: const <String, PortDirection>{},
            connections: const <String, List<BitRef>>{},
          ),
      };
      final model = _modelWith(
        topCells: cells,
        topNets: const <String, Net>{},
      );
      final hits = service.search(
        model: model,
        query: 'cell_',
        maxResults: 5,
      );
      expect(hits, hasLength(5));
    });
  });

  group('DesignSearchService.driverCellForNet', () {
    Cell dff({
      required String name,
      required int dIn,
      required int qOut,
    }) => Cell(
      name: name,
      type: r'$dff',
      parameters: const <String, String>{},
      attributes: const <String, String>{},
      portDirections: const <String, PortDirection>{
        'D': PortDirection.input,
        'Q': PortDirection.output,
      },
      connections: <String, List<BitRef>>{
        'D': <BitRef>[NetBit(dIn)],
        'Q': <BitRef>[NetBit(qOut)],
      },
    );

    test('returns the cell whose OUTPUT pin drives the net', () {
      final module = Module(
        name: 'top',
        attributes: const <String, String>{'top': '1'},
        ports: const {},
        cells: <String, Cell>{'reg_a': dff(name: 'reg_a', dIn: 3, qOut: 5)},
        nets: const <String, Net>{
          'sig': Net(
            name: 'sig',
            bits: <BitRef>[NetBit(5)],
            attributes: <String, String>{},
          ),
        },
      );
      expect(DesignSearchService.driverCellForNet(module, 'sig'), 'reg_a');
    });

    test('does NOT return a cell that only READS the net on an input pin', () {
      final module = Module(
        name: 'top',
        attributes: const <String, String>{'top': '1'},
        ports: const {},
        // reg_a reads net 5 on its D input; no cell drives it.
        cells: <String, Cell>{'reg_a': dff(name: 'reg_a', dIn: 5, qOut: 7)},
        nets: const <String, Net>{
          'sig': Net(
            name: 'sig',
            bits: <BitRef>[NetBit(5)],
            attributes: <String, String>{},
          ),
        },
      );
      expect(DesignSearchService.driverCellForNet(module, 'sig'), isNull);
    });

    test('returns null for an undriven / absent net', () {
      final module = Module(
        name: 'top',
        attributes: const <String, String>{'top': '1'},
        ports: const {},
        cells: <String, Cell>{'reg_a': dff(name: 'reg_a', dIn: 3, qOut: 5)},
        nets: const <String, Net>{
          'float': Net(
            name: 'float',
            bits: <BitRef>[NetBit(9)],
            attributes: <String, String>{},
          ),
        },
      );
      expect(DesignSearchService.driverCellForNet(module, 'float'), isNull);
      expect(DesignSearchService.driverCellForNet(module, 'missing'), isNull);
    });
  });
}
