// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_stub_writer.dart';

LibertyLibrary _lib(String path, List<LibertyCell> cells) =>
    LibertyLibrary(path: path, cells: cells);

void main() {
  group('writeLibertyStubs', () {
    test('writes one black-box module per cell, power pins as inout', () {
      final text = writeLibertyStubs(<LibertyLibrary>[
        _lib('/libs/a.lib', <LibertyCell>[
          LibertyCell(
            name: 'DFF4',
            ports: const <LibertyPort>[
              LibertyPort(name: 'VDD', direction: LibertyPortDirection.inout),
              LibertyPort(
                name: 'D',
                direction: LibertyPortDirection.input,
                msb: 3,
                lsb: 0,
              ),
              LibertyPort(
                name: 'Q',
                direction: LibertyPortDirection.output,
                msb: 0,
                lsb: 3,
              ),
            ],
          ),
        ]),
      ]);
      expect(text.cellCount, 1);
      expect(text.warnings, isEmpty);
      expect(
        text.verilog,
        contains(
          '// a.lib\n'
          '(* blackbox *)\n'
          'module DFF4 (VDD, D, Q);\n'
          '  inout VDD;\n'
          '  input [3:0] D;\n'
          '  output [0:3] Q;\n'
          'endmodule\n',
        ),
      );
    });

    test('escapes names that are not plain identifiers', () {
      final text = writeLibertyStubs(<LibertyLibrary>[
        _lib('/libs/a.lib', <LibertyCell>[
          LibertyCell(
            name: 'AND2.X',
            ports: const <LibertyPort>[
              LibertyPort(name: 'A[0]', direction: LibertyPortDirection.input),
              LibertyPort(name: 'input', direction: LibertyPortDirection.input),
              LibertyPort(name: 'Y', direction: LibertyPortDirection.output),
            ],
          ),
        ]),
      ]);
      expect(
        text.verilog,
        contains(
          'module \\AND2.X  (\\A[0] , \\input , Y);\n'
          '  input \\A[0] ;\n'
          '  input \\input ;\n'
          '  output Y;\n',
        ),
      );
    });

    test('the first library to define a cell wins, with a warning', () {
      final text = writeLibertyStubs(<LibertyLibrary>[
        _lib('/libs/first.lib', <LibertyCell>[
          LibertyCell(
            name: 'INV',
            ports: const <LibertyPort>[
              LibertyPort(name: 'A', direction: LibertyPortDirection.input),
            ],
          ),
        ]),
        _lib('/libs/second.lib', <LibertyCell>[
          LibertyCell(
            name: 'INV',
            ports: const <LibertyPort>[
              LibertyPort(name: 'B', direction: LibertyPortDirection.input),
            ],
          ),
          LibertyCell(name: 'BUF', ports: const <LibertyPort>[]),
        ]),
      ]);
      expect(text.cellCount, 2);
      expect(text.verilog, contains('module INV (A);'));
      expect(text.verilog, isNot(contains('module INV (B);')));
      expect(text.verilog, contains('module BUF ();'));
      expect(text.warnings.single, contains('/libs/first.lib'));
      expect(text.warnings.single, contains('/libs/second.lib'));
    });

    test('carries the libraries own warnings through', () {
      final text = writeLibertyStubs(<LibertyLibrary>[
        LibertyLibrary(
          path: '/libs/a.lib',
          cells: const <LibertyCell>[],
          warnings: const <String>['something odd'],
        ),
      ]);
      expect(text.warnings, <String>['something odd']);
    });

    test('leaves out a name Verilog cannot spell, with a warning', () {
      final text = writeLibertyStubs(<LibertyLibrary>[
        _lib('/libs/a.lib', <LibertyCell>[
          LibertyCell(
            name: 'X',
            ports: const <LibertyPort>[
              LibertyPort(name: 'A B', direction: LibertyPortDirection.input),
              LibertyPort(name: 'Y', direction: LibertyPortDirection.output),
            ],
          ),
        ]),
      ]);
      expect(text.verilog, contains('module X (Y);'));
      expect(text.warnings.single, contains('"A B"'));
    });
  });

  group('verilogIdentifier', () {
    test('keeps plain identifiers and escapes the rest', () {
      expect(verilogIdentifier('INVX1'), 'INVX1');
      expect(verilogIdentifier(r'a$b_1'), r'a$b_1');
      expect(verilogIdentifier('1abc'), r'\1abc ');
      expect(verilogIdentifier('module'), r'\module ');
      expect(verilogIdentifier('D[3]'), r'\D[3] ');
      expect(verilogIdentifier(''), isNull);
      expect(verilogIdentifier('a b'), isNull);
      expect(verilogIdentifier('café'), isNull);
    });
  });
}
