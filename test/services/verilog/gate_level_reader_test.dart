// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/verilog/native_netlist_reader.dart';
import 'package:netcrux/services/verilog/verilog_scanner.dart';
import 'package:path/path.dart' as p;

/// What the native reader builds from small netlists, asserted bit by bit.
/// None of this needs Yosys; `native_vs_yosys_test.dart` holds the same
/// reader to the Yosys route's model.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('gate_level_reader'));
  tearDown(() => dir.deleteSync(recursive: true));

  NativeReadOutcome read(
    String text, {
    String top = '',
    List<String> models = const <String>[],
    int bufferSize = VerilogScanner.defaultBufferSize,
    int maxTokenBytes = 64 * 1024,
  }) {
    final file = File(p.join(dir.path, 'n.v'))..writeAsStringSync(text);
    final modelFiles = <String>[
      for (var i = 0; i < models.length; i++)
        (File(p.join(dir.path, 'm$i.v'))..writeAsStringSync(models[i])).path,
    ];
    return readGateLevelNetlist(
      NativeReadRequest(
        sourceFiles: [file.path],
        cellModelFiles: modelFiles,
        topModule: top,
        bufferSize: bufferSize,
        maxTokenBytes: maxTokenBytes,
      ),
    )!;
  }

  NetlistModel model(String text, {String top = ''}) {
    final outcome = read(text, top: top);
    expect(
      outcome,
      isA<NativeReadSuccess>(),
      reason: outcome is NativeReadFallbackOutcome
          ? outcome.diagnosticLine
          : null,
    );
    return (outcome as NativeReadSuccess).model;
  }

  NativeReadFallbackOutcome declined(String text, {String top = ''}) {
    final outcome = read(text, top: top);
    expect(outcome, isA<NativeReadFallbackOutcome>());
    return outcome as NativeReadFallbackOutcome;
  }

  List<String> bits(List<BitRef> list) => [
    for (final b in list)
      switch (b) {
        NetBit(:final netId) => '$netId',
        ConstantBit() => "'${b.toJson()}",
      },
  ];

  group('bits', () {
    test('a constant assigned to a vector is least significant bit first', () {
      final m = model('''
module t (output [3:0] y);
  assign y = 4'b1010;
endmodule
''');
      expect(bits(m.modules['t']!.ports['y']!.bits), ["'0", "'1", "'0", "'1"]);
    });

    test('x, z, ? and the extension of an unknown leading digit', () {
      final m = model('''
module t (output [11:0] a, output [3:0] b, output [3:0] c, output [7:0] d);
  assign a = 12'hx3;
  assign b = 4'b1?z0;
  assign c = 4'dx;
  assign d = 8'd200;
endmodule
''');
      final ports = m.modules['t']!.ports;
      expect(
        bits(ports['a']!.bits),
        ["'1", "'1", "'0", "'0"] +
            ["'x", "'x", "'x", "'x", "'x", "'x", "'x", "'x"],
      );
      expect(bits(ports['b']!.bits), ["'0", "'z", "'z", "'1"]);
      expect(bits(ports['c']!.bits), ["'x", "'x", "'x", "'x"]);
      expect(
        bits(ports['d']!.bits),
        ["'0", "'0", "'0", "'1", "'0", "'0", "'1", "'1"],
      );
    });

    test('a concatenation lists its last element first; {n{x}} repeats', () {
      final m = model('''
module t (input [1:0] a, input b, output [4:0] y, output [3:0] r);
  assign y = {a, 1'b1, b, a[0]};
  assign r = {2{a}};
endmodule
''');
      final t = m.modules['t']!;
      final a = bits(t.ports['a']!.bits);
      final b = bits(t.ports['b']!.bits).single;
      expect(bits(t.ports['y']!.bits), [a[0], b, "'1", a[0], a[1]]);
      expect(bits(t.ports['r']!.bits), [a[0], a[1], a[0], a[1]]);
    });

    test('selects follow the declared range, ascending or descending', () {
      final m = model('''
module t (input [7:4] hi, input [0:3] up, output [1:0] h, output u0, output [1:0] us);
  assign h = hi[5:4];
  assign u0 = up[0];
  assign us = up[1:2];
endmodule
''');
      final t = m.modules['t']!;
      final hi = bits(t.ports['hi']!.bits);
      final up = bits(t.ports['up']!.bits);
      // [7:4]: hi[4] is bit 0. [0:3]: up[3] is bit 0.
      expect(bits(t.ports['h']!.bits), [hi[0], hi[1]]);
      expect(bits(t.ports['u0']!.bits), [up[3]]);
      expect(bits(t.ports['us']!.bits), [up[1], up[2]]);
    });

    test('aliased nets share bits and a supply net is a constant', () {
      final m = model('''
module t (input a, output y, output z);
  supply1 hi;
  wire w;
  assign w = a;
  assign y = w;
  assign z = hi;
endmodule
''');
      final t = m.modules['t']!;
      expect(bits(t.ports['y']!.bits), bits(t.ports['a']!.bits));
      expect(bits(t.nets['w']!.bits), bits(t.ports['a']!.bits));
      expect(bits(t.ports['z']!.bits), ["'1"]);
      expect(bits(t.nets['hi']!.bits), ["'1"]);
    });

    test('bits are numbered from 2 over ports, then cells, then nets', () {
      final m = model('''
module t (input a, output y);
  wire floating;
  wire mid;
  INV u (.A(a), .Y(mid));
  INV v (.A(mid), .Y(y));
endmodule
''');
      final t = m.modules['t']!;
      expect(bits(t.ports['a']!.bits), ['2']);
      expect(bits(t.ports['y']!.bits), ['3']);
      expect(bits(t.cells['u']!.connections['Y']!), ['4']);
      expect(bits(t.nets['floating']!.bits), ['5']);
    });
  });

  group('instances', () {
    test('cells and pins are in name order whatever the source order', () {
      final m = model('''
module t (input a, output y);
  wire n;
  INV zz (.Y(n), .A(a));
  INV aa (.Y(y), .A(n));
endmodule
''');
      final t = m.modules['t']!;
      expect(t.cells.keys, ['aa', 'zz']);
      expect(t.cells['zz']!.connections.keys, ['A', 'Y']);
      expect(t.nets.keys, ['a', 'n', 'y']);
    });

    test('positional connections follow the port order of a later module', () {
      final m = model('''
module t (input a, input b, output y);
  leaf u (b, a, y);
endmodule
module leaf (input p, input q, output r);
endmodule
''', top: 't');
      final u = m.modules['t']!.cells['u']!;
      expect(u.connections.keys, ['p', 'q', 'r']);
      expect(bits(u.connections['p']!), bits(m.modules['t']!.ports['b']!.bits));
      expect(u.portDirections, {
        'p': PortDirection.input,
        'q': PortDirection.input,
        'r': PortDirection.output,
      });
    });

    test(r'positional pins of an undefined module are named $1, $2, ...', () {
      final m = model('''
module t (input a, output y);
  MYSTERY u (a, y);
endmodule
''');
      final u = m.modules['t']!.cells['u']!;
      expect(u.connections.keys, [r'$1', r'$2']);
      // The wiring decides the directions.
      expect(u.portDirections, {
        r'$1': PortDirection.input,
        r'$2': PortDirection.output,
      });
    });

    test('an empty connection is an empty bit list', () {
      final m = model('''
module t (input a);
  CELL u (.A(a), .B());
endmodule
''');
      expect(m.modules['t']!.cells['u']!.connections['B'], isEmpty);
    });

    test(
      'a name used in a connection and nowhere else is one implicit net',
      () {
        final m = model('''
module t (input a);
  CELL u (.A(a), .B(loose));
  CELL v (.A(loose), .B());
endmodule
''');
        final t = m.modules['t']!;
        expect(t.nets.containsKey('loose'), isTrue);
        expect(
          bits(t.cells['u']!.connections['B']!),
          bits(t.cells['v']!.connections['A']!),
        );
      },
    );

    test('src locations span the instance, the net and the module', () {
      final m = model('''
module t (input a);
  wire w;
  CELL u (.A(a),
          .B(w));
endmodule
''');
      final t = m.modules['t']!;
      expect(t.attributes['src'], endsWith('n.v:1.1-5.10'));
      expect(t.nets['w']!.attributes['src'], endsWith('n.v:2.8-2.9'));
      expect(t.cells['u']!.attributes['src'], endsWith('n.v:3.8-4.17'));
    });

    test('names with escapes and trailing space keep their text', () {
      final m = model(r'''
module t (input a);
  wire \bus[3] ;
  CELL \u1/x[2]  (.A(a), .B(\bus[3] ));
endmodule
''');
      final t = m.modules['t']!;
      expect(t.nets.keys, contains('bus[3]'));
      expect(t.cells.keys, ['u1/x[2]']);
    });
  });

  group('hierarchy', () {
    const hier = '''
module leaf (input a, output y); INV u (.A(a), .Y(y)); endmodule
module mid (input a, output y); leaf l (.a(a), .y(y)); endmodule
module top (input a, output y); mid m (.a(a), .y(y)); endmodule
module stray (input a, output y); leaf l (.a(a), .y(y)); endmodule
''';

    test('the top is the module that is not instantiated and is highest', () {
      final m = model(hier);
      // `top` and `stray` are both uninstantiated; `top` is deeper.
      expect(m.topModule!.name, 'top');
      expect(m.modules.keys, containsAll(['top', 'mid', 'leaf']));
      expect(m.modules.containsKey('stray'), isFalse);
    });

    test('of equal candidates the later definition is the top', () {
      final m = model('''
module one (input a); CELL u (.A(a)); endmodule
module two (input a); CELL u (.A(a)); endmodule
''');
      expect(m.topModule!.name, 'two');
    });

    test('a named top keeps what it reaches and drops the rest', () {
      final m = model(hier, top: 'mid');
      expect(m.topModule!.name, 'mid');
      expect(m.modules.keys.toSet(), {'mid', 'leaf'});
    });

    test('a missing named top declines', () {
      final d = declined(hier, top: 'nope');
      expect(d.stop, NativeReaderStop.inconsistent);
      expect(d.message, contains('"nope"'));
    });
  });

  group('cell definitions', () {
    const models = [
      '''
(* blackbox *)
module INV (input A, output Y);
endmodule
module BUS (input [3:0] D, output [3:0] Q);
endmodule
''',
    ];

    test('a model file gives directions and a black-box stub', () {
      final outcome =
          read('''
module t (input a, output y, input [3:0] d, output [3:0] q);
  INV u (.A(a), .Y(y), .X(a));
  BUS b (.D(d), .Q(q));
endmodule
''', models: models)
              as NativeReadSuccess;
      final t = outcome.model.modules['t']!;
      expect(t.cells['u']!.portDirections['A'], PortDirection.input);
      expect(t.cells['u']!.portDirections['Y'], PortDirection.output);
      // A pin the model lacks is inferred from the wiring: `a` is an input
      // port, so it can only be read.
      expect(t.cells['u']!.portDirections['X'], PortDirection.input);
      expect(outcome.model.modules['INV']!.isBlackBox, isTrue);
      expect(outcome.model.modules['BUS']!.ports['D']!.bits, hasLength(4));
      expect(outcome.report.undeclaredPins, ['INV.X']);
      expect(outcome.report.types, isEmpty);
    });

    test('a module in the sources wins over a model of the same name', () {
      final outcome =
          read(
                '''
module INV (input A, output Y); endmodule
module t (input a, output y);
  INV u (.A(a), .Y(y));
endmodule
''',
                models: models,
                top: 't',
              )
              as NativeReadSuccess;
      expect(outcome.model.modules['INV']!.isBlackBox, isFalse);
    });

    test('a width that disagrees with the definition is a warning', () {
      final outcome =
          read('''
module t (input [1:0] d, output [3:0] q);
  BUS b (.D(d), .Q(q));
endmodule
''', models: models)
              as NativeReadSuccess;
      expect(outcome.warnings.single, contains('connected to 2 bits'));
      expect(outcome.warnings.single, contains('declared 4 wide'));
    });
  });

  group('the reader does not guess', () {
    final cases = <String, (String, String)>{
      'always': (
        'module t (input a);\n  always @(a) begin end\nendmodule',
        'an `always` block',
      ),
      'initial': (
        'module t (input a);\n  initial a = 0;\nendmodule',
        'an `initial` block',
      ),
      'generate': (
        'module t (input a);\n  generate endgenerate\nendmodule',
        'a `generate` construct',
      ),
      'function': (
        'module t (input a);\n  function f; input x; f = x; endfunction\nendmodule',
        'a `function` construct',
      ),
      'parameter': (
        'module t (input a);\n  parameter W = 1;\nendmodule',
        '`parameter` declarations',
      ),
      'module parameter list': (
        'module t #(parameter W = 1) (input a);\nendmodule',
        'a module parameter list',
      ),
      'reg': ('module t (input a);\n  reg r;\nendmodule', 'the `reg` keyword'),
      'output reg': (
        'module t (output reg y);\nendmodule',
        'the `reg` keyword',
      ),
      'primitive gate': (
        'module t (input a, b, output y);\n  and g (y, a, b);\nendmodule',
        'the `and` keyword',
      ),
      'unnamed instance': (
        'module t (input a);\n  CELL (a);\nendmodule',
        'an instance without a name',
      ),
      'instance override': (
        'module t (input a);\n  CELL #(1) u (a);\nendmodule',
        'an instance parameter override or delay',
      ),
      'instance array': (
        'module t (input a);\n  CELL u [1:0] (a);\nendmodule',
        'an array of instances',
      ),
      'expression': (
        'module t (input a, b);\n  CELL u (.A(a & b));\nendmodule',
        'an expression in a port connection',
      ),
      'assign expression': (
        'module t (input a, b, output y);\n  assign y = a & b;\nendmodule',
        'an expression in an assignment',
      ),
      'unsized constant': (
        'module t (input a);\n  CELL u (.A(1));\nendmodule',
        'an unsized constant',
      ),
      'wildcard': (
        'module t (input a);\n  CELL u (.*);\nendmodule',
        'a wildcard port connection',
      ),
      'implicit named': (
        'module t (input a);\n  CELL u (.a);\nendmodule',
        'an implicit named port connection',
      ),
      'mixed connections': (
        'module t (input a);\n  CELL u (.A(a), a);\nendmodule',
        'named and positional connections in one instance',
      ),
      'net assignment': (
        'module t (input a);\n  wire w = a;\nendmodule',
        'a net declaration with an assignment',
      ),
      'indexed part select': (
        'module t (input [7:0] a);\n  CELL u (.A(a[0 +: 2]));\nendmodule',
        'an indexed part select',
      ),
      'define': (
        '`define X 1\nmodule t (input a); endmodule',
        'the compiler directive `define',
      ),
      'include': (
        '`include "x.v"\nmodule t (input a); endmodule',
        'the compiler directive `include',
      ),
      'package': (
        'package p; endpackage\nmodule t (input a); endmodule',
        'the `package` keyword',
      ),
      'primitive def': (
        'primitive u (y, a); output y; input a; table 0 : 1; endtable endprimitive',
        'a `primitive` construct',
      ),
      'specify': (
        'module t (input a);\n  specify endspecify\nendmodule',
        'a `specify` construct',
      ),
    };
    for (final MapEntry(key: name, value: spec) in cases.entries) {
      test(name, () {
        final d = declined(spec.$1);
        expect(d.stop, NativeReaderStop.unsupported, reason: d.diagnosticLine);
        expect(d.message, contains(spec.$2));
        expect(d.line, greaterThan(0));
        expect(d.diagnosticLine, contains('Yosys reads this design instead'));
      });
    }

    test('the line is the line of the construct', () {
      final d = declined(
        'module t (input a);\n\n\n  always @(a) begin end\nendmodule',
      );
      expect(d.line, 4);
      expect(d.path, endsWith('n.v'));
      expect(d.diagnosticLine, startsWith('${d.path}:4: Warning:'));
    });
  });

  group('malformed and inconsistent input', () {
    test('a truncated module', () {
      final d = declined('module t (input a);\n  CELL u (.A(a)');
      expect(d.stop, NativeReaderStop.malformed);
      expect(d.diagnosticLine, contains('could not read this file'));
    });

    test('a stray token before any module', () {
      expect(declined('hello').stop, NativeReaderStop.malformed);
    });

    test('an undeclared net in an assign', () {
      final d = declined('module t (input a);\n  assign ghost = a;\nendmodule');
      expect(d.stop, NativeReaderStop.inconsistent);
      expect(d.message, contains('"ghost" is not declared'));
    });

    test('mismatched assign widths, selects out of range', () {
      expect(
        declined(
          'module t (input [1:0] a, output y);\n  assign y = a;\nendmodule',
        ).stop,
        NativeReaderStop.inconsistent,
      );
      expect(
        declined(
          'module t (input [1:0] a);\n  CELL u (.A(a[2]));\nendmodule',
        ).message,
        contains('select outside "a"'),
      );
    });

    test('duplicates are named', () {
      expect(
        declined(
          'module t (input a); endmodule\nmodule t (input a); endmodule',
        ).message,
        contains('module "t" is defined more than once'),
      );
      expect(
        declined(
          'module t (input a);\n  CELL u (.A(a));\n  CELL u (.A(a));\nendmodule',
        ).message,
        contains('instance name "u" is used twice'),
      );
      expect(
        declined(
          'module t (input a);\n  CELL u (.A(a), .A(a));\nendmodule',
        ).message,
        contains('pin "A"'),
      );
      expect(
        declined('module t (input a, input a); endmodule').message,
        contains('"a" is declared twice'),
      );
    });

    test('a net tied to two constants', () {
      final d = declined('''
module t (output y);
  supply0 lo;
  supply1 hi;
  assign lo = hi;
endmodule
''');
      expect(d.message, contains('two different constants'));
    });

    test('a module that instantiates itself, directly or around a loop', () {
      expect(
        declined(
          'module t (input a); t u (.a(a)); endmodule',
          top: 't',
        ).message,
        contains('instantiates itself'),
      );
      expect(
        declined('''
module a (input x); b u (.x(x)); endmodule
module b (input x); a u (.x(x)); endmodule
''', top: 'a').message,
        contains('instantiates itself'),
      );
    });

    test('a missing source file declines instead of throwing', () {
      final outcome = readGateLevelNetlist(
        NativeReadRequest(sourceFiles: [p.join(dir.path, 'absent.v')]),
      );
      expect(outcome, isA<NativeReadFallbackOutcome>());
      expect(
        (outcome! as NativeReadFallbackOutcome).message,
        contains('cannot be opened'),
      );
    });
  });

  test('a tiny read buffer builds the same model as a large one', () {
    const text = r'''
`timescale 1ns/1ps
module leaf (input a, b, output y);
  wire t;
  NAND2 \u0/g (.A(a), .B(b), .Y(t));
  INV g1 (t, y);
endmodule
module t (input [3:0] d, output [3:0] q);
  wire [3:0] n;
  leaf l0 (.a(d[0]), .b(d[1]), .y(n[0]));
  leaf l1 (d[2], d[3], n[1]);
  assign q = {n[1:0], 2'b01};
endmodule
''';
    final reference = (read(text, top: 't') as NativeReadSuccess).model;
    for (final size in const [48, 61, 100, 256]) {
      final small =
          read(text, top: 't', bufferSize: size, maxTokenBytes: 40)
              as NativeReadSuccess;
      expect(small.model, reference, reason: 'buffer $size');
    }
  });
}
