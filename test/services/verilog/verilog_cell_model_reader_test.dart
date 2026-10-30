// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/verilog/verilog_cell_model_reader.dart';

void main() {
  test('reads ANSI and non-ANSI headers and skips the bodies', () {
    final file = readCellModelText('''
`timescale 1ns/1ps
`define VENDOR_X 1
`ifdef VENDOR_X
primitive udp_dff (q, d, clk);
  output q; input d, clk; reg q;
  table 0 r : ? : 0; endtable
endprimitive
module DFF1 (input D, input CK, output reg Q, output QN);
  specify (CK => Q) = 0.1; endspecify
  always @(posedge CK) Q <= D;
  assign QN = ~Q;
endmodule
`endif
module NAND2 (Y, A, B);
  output Y;
  input A, B;
  function f; input x; f = x; endfunction
  assign Y = ~(A & B);
endmodule
module BUS (input [3:0] D, input [W-1:0] E, output [0:1] Z, inout P);
endmodule
''');
    expect(file.cells.map((c) => c.name), ['DFF1', 'NAND2', 'BUS']);
    final dff = file.cells[0];
    expect(dff.ports.map((p) => p.name), ['D', 'CK', 'Q', 'QN']);
    expect(dff.ports.map((p) => p.direction), [
      PortDirection.input,
      PortDirection.input,
      PortDirection.output,
      PortDirection.output,
    ]);
    final nand = file.cells[1];
    expect(nand.ports.map((p) => p.name), ['Y', 'A', 'B']);
    expect(nand.ports.map((p) => p.direction), [
      PortDirection.output,
      PortDirection.input,
      PortDirection.input,
    ]);
    final bus = file.cells[2];
    expect(bus.ports[0].width, 4);
    expect(bus.ports[1].width, isNull);
    expect(bus.ports[2].width, 2);
    expect(bus.ports[2].msb, 0);
    expect(bus.ports[3].direction, PortDirection.inout);
  });

  test('a module twice in a file keeps the first and warns', () {
    final file = readCellModelText('''
module A (input x); endmodule
module A (output x); endmodule
''');
    expect(file.cells, hasLength(1));
    expect(file.warnings.single, contains('"A"'));
  });
}
