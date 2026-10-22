// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Name mapping for what Formal and Flow send NetCrux: hierarchical register
// names (generate blocks, escaped identifiers, Yosys `$`-names, a VHDL
// design lowered to Verilog), a property's `<file>:<line>`, and the signals
// a property reads. Expectations come from the RTL each case stands for,
// never from NetCrux's own output.

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/services/remote/cxp/cxp_design_names.dart';
import 'package:netcrux/services/remote/cxp/inbound_property.dart';
import 'package:netcrux/services/remote/cxp/netcrux_name_resolver.dart';

import '../../../helpers/formal_flow_design.dart';

/// A design whose names are the awkward ones real elaborations produce:
/// a generate-block instance (`gen_lane[1]`), an escaped register
/// (`\cnt.q `), a Yosys `$`-name with a `.` in it, and the instance and
/// signal names `ghdl --synth --out=verilog` writes for a VHDL entity
/// (lower case, `_` for hierarchy: `u_fifo`, `wr_ptr`).
NetlistModel _awkwardDesign() {
  Cell cell(String name, String type, {List<int> q = const <int>[]}) => Cell(
    name: name,
    type: type,
    parameters: const <String, String>{},
    attributes: const <String, String>{},
    portDirections: <String, PortDirection>{
      if (q.isNotEmpty) 'Q': PortDirection.output,
    },
    connections: <String, List<BitRef>>{
      if (q.isNotEmpty) 'Q': <BitRef>[for (final b in q) NetBit(b)],
    },
  );
  Net net(String name, List<int> bits) => Net(
    name: name,
    bits: <BitRef>[for (final b in bits) NetBit(b)],
    attributes: const <String, String>{},
  );
  final lane = Module(
    name: 'lane',
    attributes: const <String, String>{},
    ports: const {},
    cells: <String, Cell>{
      'cnt.q': cell('cnt.q', r'$dff', q: <int>[2]),
      r'$auto$ff.cc:266:slice$1234': cell(
        r'$auto$ff.cc:266:slice$1234',
        r'$dff',
        q: <int>[3],
      ),
    },
    nets: <String, Net>{
      'cnt.q': net('cnt.q', <int>[2]),
      r'$auto$ff.cc:266:slice$1234_Q': net(
        r'$auto$ff.cc:266:slice$1234_Q',
        <int>[3],
      ),
    },
  );
  final fifo = Module(
    name: 'fifo',
    attributes: const <String, String>{},
    ports: const {},
    cells: <String, Cell>{
      'wr_ptr_reg': cell('wr_ptr_reg', r'$dff', q: <int>[2, 3, 4]),
    },
    nets: <String, Net>{
      'wr_ptr': net('wr_ptr', <int>[2, 3, 4]),
    },
  );
  final top = Module(
    name: 'top',
    attributes: const <String, String>{'top': '1'},
    ports: const {},
    cells: <String, Cell>{
      'gen_lane[1]': cell('gen_lane[1]', 'lane'),
      'u_fifo': cell('u_fifo', 'fifo'),
      'u_div.cnt_q_reg': cell('u_div.cnt_q_reg', r'$dff', q: <int>[5]),
    },
    nets: <String, Net>{
      'u_div.cnt_q': net('u_div.cnt_q', <int>[5]),
    },
  );
  return NetlistModel(
    creator: 'hand-written',
    modules: <String, Module>{'top': top, 'lane': lane, 'fifo': fifo},
  );
}

void main() {
  group('NetcruxNameResolver.splitHierarchicalPath', () {
    List<String> split(String path) =>
        NetcruxNameResolver.splitHierarchicalPath(path);

    test('splits on . and /', () {
      expect(split('top.u_div/cnt_q'), <String>['top', 'u_div', 'cnt_q']);
    });

    test('an escaped identifier is one segment, read as Yosys names it', () {
      expect(split(r'top.\cnt.q .x'), <String>['top', 'cnt.q', 'x']);
      expect(split(r'top.\a/b '), <String>['top', 'a/b']);
    });

    test(r'a $-name runs to the end, dots and all', () {
      expect(split(r'top.lane.$auto$ff.cc:266:slice$1234'), <String>[
        'top',
        'lane',
        r'$auto$ff.cc:266:slice$1234',
      ]);
    });

    test('a bracketed index stays on its segment', () {
      expect(split('top.gen_lane[1].cnt'), <String>[
        'top',
        'gen_lane[1]',
        'cnt',
      ]);
      expect(split('top.mem[a.b].q'), <String>['top', 'mem[a.b]', 'q']);
    });

    test('escapeSegment round-trips a name with a separator in it', () {
      for (final name in <String>['cnt.q', 'a/b', 'plain', r'$x.y']) {
        final path = 'top.${NetcruxNameResolver.escapeSegment(name)}';
        expect(split(path), <String>['top', name], reason: path);
      }
    });
  });

  group('NetcruxNameResolver keeps the fixed-convention kinds verbatim', () {
    const resolver = NetcruxNameResolver();

    test('a property path keeps its /', () {
      expect(
        resolver.toLocal(
          const ElementId(kind: ElementKind.property, path: 'rtl/top.sv:20'),
        ),
        'rtl/top.sv:20',
      );
    });

    test('a timing path id and a cell name pass through', () {
      expect(
        resolver.toLocal(
          const ElementId(kind: ElementKind.timingPath, path: 'run_1/3'),
        ),
        'run_1/3',
      );
      expect(
        resolver.toLocal(
          const ElementId(kind: ElementKind.cell, path: 'top.u_div/cnt_reg'),
        ),
        'top.u_div/cnt_reg',
      );
    });

    test('a / inside an escaped segment is not a separator', () {
      expect(
        resolver.toLocal(
          const ElementId(kind: ElementKind.signal, path: r'top/\a/b '),
        ),
        r'top.\a/b ',
      );
    });
  });

  group('scopeOfHierarchicalName', () {
    final model = _awkwardDesign();

    test('a generate-block instance is walked into', () {
      final placed = scopeOfHierarchicalName(model, r'top.gen_lane[1].\cnt.q ');
      expect(placed!.scope.path, <String>['gen_lane[1]']);
      expect(placed.leaf, 'cnt.q');
      expect(
        findNetNamed(placed.scope.resolve(model)!, placed.leaf),
        isNotNull,
      );
    });

    test(r'a $-name leaf keeps its dots', () {
      final placed = scopeOfHierarchicalName(
        model,
        r'top.gen_lane[1].$auto$ff.cc:266:slice$1234_Q',
      );
      expect(placed!.scope.path, <String>['gen_lane[1]']);
      expect(placed.leaf, r'$auto$ff.cc:266:slice$1234_Q');
    });

    test('a VHDL-lowered name resolves with its bus bit stripped', () {
      final placed = scopeOfHierarchicalName(model, 'top.u_fifo.wr_ptr[2]');
      expect(placed!.scope.path, <String>['u_fifo']);
      final net = findNetNamed(placed.scope.resolve(model)!, placed.leaf);
      expect(net?.name, 'wr_ptr');
    });

    test('a flattened name stays one leaf of the top', () {
      final placed = scopeOfHierarchicalName(model, 'top.u_div.cnt_q');
      expect(placed!.scope.isRoot, isTrue);
      expect(placed.leaf, 'u_div.cnt_q');
      expect(
        findNetNamed(placed.scope.resolve(model)!, placed.leaf),
        isNotNull,
      );
    });

    test('a name not rooted at this top is not placed', () {
      expect(scopeOfHierarchicalName(model, 'tb.dut.cnt_q'), isNull);
      expect(scopeOfHierarchicalName(model, 'cnt_q'), isNull);
    });
  });

  group('registerOutputNetName', () {
    test('names the net the register drives', () {
      final model = formalFlowDesign();
      final top = model.modules['top']!;
      expect(registerOutputNetName(top, 'cnt_reg'), 'cnt_q');
      expect(registerOutputNetName(top, 'esc_reg'), 'esc.q');
      expect(registerOutputNetName(top, 'g1'), isNull);
    });
  });

  group('PropertyLocation.parse', () {
    test('reads <file>:<line> and <file>:<line>:<col>', () {
      final a = PropertyLocation.parse('rtl/top.sv:20')!;
      expect((a.file, a.line, a.column), ('rtl/top.sv', 20, null));
      final b = PropertyLocation.parse('rtl/top.sv:20:5')!;
      expect((b.file, b.line, b.column), ('rtl/top.sv', 20, 5));
    });

    test('refuses what a project-relative path is not', () {
      for (final bad in <String>[
        '/etc/passwd:1',
        r'C:\x.sv:1',
        '../outside.sv:3',
        'rtl/../../x.sv:3',
        'rtl/top.sv',
        'rtl/top.sv:0',
        'rtl/top.sv:x',
        'a\u0000.sv:1',
        '',
      ]) {
        expect(PropertyLocation.parse(bad), isNull, reason: bad);
      }
    });
  });

  group('designSourceFor', () {
    const location = PropertyLocation(file: 'rtl/top.sv', line: 20);

    test('matches whole trailing segments of a design source', () {
      expect(
        designSourceFor(<String>[
          '/w/a/rtl/top.sv',
          '/w/a/rtl/sub.sv',
        ], location),
        '/w/a/rtl/top.sv',
      );
      expect(designSourceFor(<String>['/w/a/xrtl/top.sv'], location), isNull);
    });

    test('two design sources it could name are ambiguous', () {
      expect(
        designSourceFor(<String>[
          '/w/a/rtl/top.sv',
          '/w/b/rtl/top.sv',
        ], location),
        isNull,
      );
    });

    test('a file outside the design is never named', () {
      expect(designSourceFor(const <String>[], location), isNull);
    });
  });

  group('propertyIdentifiers', () {
    test('keeps signals, drops keywords, system calls, labels, comments', () {
      expect(
        propertyIdentifiers(
          'p_full: assert property (@(posedge clk) disable iff (rst) '
          r"wr_en && 4'hF |-> ##1 !full && $past(cnt_q)); // ignored_name",
        ),
        <String>['clk', 'rst', 'wr_en', 'full', 'cnt_q'],
      );
    });

    test('reads hierarchical and escaped names whole', () {
      expect(
        propertyIdentifiers(r'assert property (u_sub.state |-> \cnt.q );'),
        <String>['u_sub.state', 'cnt.q'],
      );
    });
  });

  group('placePropertyReads', () {
    final model = formalFlowDesign();

    test("finds the property's module by its src span and its signals", () {
      final reads = placePropertyReads(
        model: model,
        current: null,
        location: const PropertyLocation(file: kFormalFlowTopFile, line: 22),
        identifiers: const <String>['clk', 'u_sub.state', 'cnt_q', 'nope'],
      )!;
      expect(reads.scope.isRoot, isTrue);
      expect(reads.local, <String>['clk', 'cnt_q']);
      expect(reads.otherScopes, <String>['u_sub.state']);
    });

    test('a property in a submodule is shown in an instance of it', () {
      final reads = placePropertyReads(
        model: model,
        current: HierarchyNode.rootOf(model),
        location: const PropertyLocation(file: kFormalFlowSubFile, line: 5),
        identifiers: const <String>['state', 'i'],
      )!;
      expect(reads.scope.path, <String>['u_sub']);
      expect(reads.local, <String>['state', 'i']);
    });

    test('a line no module was read from places nothing', () {
      expect(
        placePropertyReads(
          model: model,
          current: null,
          location: const PropertyLocation(file: 'rtl/other.sv', line: 3),
          identifiers: const <String>['clk'],
        ),
        isNull,
      );
    });
  });

  group('readPropertyStatement', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('nc_prop_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads from the line to the end of the statement', () async {
      final file = File('${dir.path}/top.sv')
        ..writeAsStringSync(formalFlowTopSource());
      final text = await readPropertyStatement(file.path, 22);
      expect(text, contains('u_sub.state |-> cnt_q[0]);'));
      expect(text, isNot(contains('endmodule')));
    });

    test('is bounded, and a line past the end reads nothing', () async {
      final file = File('${dir.path}/long.sv')
        ..writeAsStringSync('assert property (\n${'a &&\n' * 500}b);\n');
      final text = await readPropertyStatement(file.path, 1);
      expect(text!.length, lessThanOrEqualTo(kPropertyTextMaxChars));
      expect(
        '\n'.allMatches(text).length,
        lessThanOrEqualTo(kPropertyTextMaxLines),
      );
      expect(await readPropertyStatement(file.path, 100000), isNull);
    });
  });
}
