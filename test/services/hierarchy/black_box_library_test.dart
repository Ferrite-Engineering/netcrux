// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/search/design_search_service.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

/// The SERV SoC synthesized for an iCE40 (see the fixture's PROVENANCE.md):
/// `synth_ice40` leaves the whole cell library in the design as black-box
/// modules, and every cell of the top module instantiates one. The first
/// beta tester to open such a netlist found 966 pushable "scopes" with five
/// ports and nothing inside, and typed a cell name into the hierarchy
/// filter, which only sees scopes, and concluded cells could not be found.
void main() {
  late NetlistModel model;

  setUpAll(() {
    final bytes = File(
      'test/fixtures/netlist/serv_ice40/captured/serv_ice40.netlist.json.gz',
    ).readAsBytesSync();
    model = const StreamingYosysJsonReader().parse(
      utf8.decode(gzip.decode(bytes)),
    );
  });

  test('the library modules are there, and are black boxes', () {
    expect(model.modules, hasLength(51));
    expect(model.modules['SB_LUT4']!.isBlackBox, isTrue);
    expect(model.modules['SB_DFF']!.isBlackBox, isTrue);
    expect(model.modules['SB_RAM40_4K']!.isBlackBox, isTrue);
    expect(model.modules['service']!.isBlackBox, isFalse);
    expect(model.modules['service']!.cells, hasLength(966));
  });

  test('the hierarchy is one scope: the top, with every cell a leaf', () {
    final root = HierarchyNode.rootOf(model)!;
    expect(root.moduleName, 'service');
    expect(root.childInstanceNames(model), isEmpty);
    expect(
      root.child(model, 'servant.servile.cpu.alu.add_cy_r_SB_LUT4_I3_1'),
      isNull,
      reason: 'an SB_LUT4 instance is a cell to draw, not a scope to enter',
    );
  });

  test('search finds those cells as cells, never as instances', () {
    final results = const DesignSearchService().search(
      model: model,
      query: 'alu.add',
    );
    expect(results, isNotEmpty);
    // Nets named after those cells match too; what must never appear is an
    // instance, the push-into kind the library modules used to produce.
    final kinds = results.map((r) => r.kind).toSet();
    expect(kinds, contains(SearchResultKind.cell));
    expect(kinds, isNot(contains(SearchResultKind.instance)));
    expect(
      results.map((r) => r.name),
      contains('servant.servile.cpu.alu.add_cy_r_SB_LUT4_I3_1'),
    );
  });
}
