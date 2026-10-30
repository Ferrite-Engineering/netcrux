// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/verilog/verilog_scanner.dart';

/// The Verilog keywords the gate-level reader tells apart, interned first in
/// every reader's [Interner] so an identifier id below [count] is a keyword
/// and the ids are compile-time constants.
///
/// A keyword written as an escaped identifier (`\module `) is an ordinary
/// name; the scanner's `escaped` flag is what separates them.
abstract final class VerilogKeywords {
  /// `module`.
  static const int module = 0;

  /// `macromodule`.
  static const int macromodule = 1;

  /// `endmodule`.
  static const int endmodule = 2;

  /// `input`.
  static const int input = 3;

  /// `output`.
  static const int output = 4;

  /// `inout`.
  static const int inout = 5;

  /// `wire`.
  static const int wire = 6;

  /// `tri`.
  static const int tri = 7;

  /// `supply0`.
  static const int supply0 = 8;

  /// `supply1`.
  static const int supply1 = 9;

  /// `assign`.
  static const int assign = 10;

  /// `primitive`.
  static const int primitive = 11;

  /// `endprimitive`.
  static const int endprimitive = 12;

  /// `function`.
  static const int function = 13;

  /// `endfunction`.
  static const int endfunction = 14;

  /// `task`.
  static const int task = 15;

  /// `endtask`.
  static const int endtask = 16;

  /// `specify`.
  static const int specify = 17;

  /// `endspecify`.
  static const int endspecify = 18;

  /// `table`.
  static const int table = 19;

  /// `endtable`.
  static const int endtable = 20;

  /// `generate`.
  static const int generate = 21;

  /// `endgenerate`.
  static const int endgenerate = 22;

  /// `reg`.
  static const int reg = 23;

  /// `signed`.
  static const int signed = 24;

  /// `unsigned`.
  static const int unsigned = 25;

  /// `logic`.
  static const int logic = 26;

  /// `var`.
  static const int variable = 27;

  /// Every keyword, in id order. The first [named] entries are the ones with
  /// a constant above; the rest are reserved words a structural netlist
  /// never contains and the reader names when it meets one.
  static const List<String> words = <String>[
    'module', 'macromodule', 'endmodule', 'input', 'output', 'inout', //
    'wire', 'tri', 'supply0', 'supply1', 'assign', 'primitive',
    'endprimitive', 'function', 'endfunction', 'task', 'endtask', 'specify',
    'endspecify', 'table', 'endtable', 'generate', 'endgenerate', 'reg',
    'signed', 'unsigned', 'logic', 'var',
    // Reserved words, in no significant order.
    'always', 'always_comb', 'always_ff', 'always_latch', 'initial', 'final',
    'genvar', 'parameter', 'localparam', 'defparam', 'integer', 'real',
    'realtime', 'time', 'event', 'wand', 'wor', 'tri0', 'tri1', 'triand',
    'trior', 'trireg', 'uwire', 'and', 'or', 'nand', 'nor', 'xor', 'xnor',
    'not', 'buf', 'bufif0', 'bufif1', 'notif0', 'notif1', 'pullup',
    'pulldown', 'nmos', 'pmos', 'rnmos', 'rpmos', 'cmos', 'rcmos', 'tran',
    'rtran', 'tranif0', 'tranif1', 'rtranif0', 'rtranif1', 'if', 'else',
    'begin', 'end', 'case', 'casex', 'casez', 'endcase', 'for', 'while',
    'forever', 'repeat', 'wait', 'fork', 'join', 'disable', 'force',
    'release', 'deassign', 'class', 'endclass', 'interface', 'endinterface',
    'package', 'endpackage', 'program', 'endprogram', 'typedef', 'enum',
    'struct', 'union', 'bit', 'byte', 'shortint', 'int', 'longint', 'string',
    'import', 'export', 'modport', 'clocking', 'endclocking', 'config',
    'endconfig', 'library', 'include', 'incdir', 'design', 'instance', 'cell',
    'liblist', 'use', 'automatic', 'scalared', 'vectored', 'small', 'medium',
    'large', 'highz0', 'highz1', 'strong0', 'strong1', 'weak0', 'weak1',
    'pull0', 'pull1', 'edge', 'posedge', 'negedge', 'ifnone', 'specparam',
    'pulsestyle_onevent', 'pulsestyle_ondetect', 'showcancelled',
    'noshowcancelled', 'assert', 'assume', 'cover', 'property', 'sequence',
    'let', 'checker', 'endchecker', 'covergroup', 'endgroup', 'bind', 'alias',
    'interconnect', 'nettype', 'soft', 'this', 'super', 'new', 'null',
    'void', 'static', 'const', 'ref', 'inside', 'unique', 'unique0',
    'priority', 'return', 'break', 'continue', 'do', 'foreach',
  ];

  /// How many words are keywords; an identifier id below this is one.
  static int get count => words.length;

  /// Interns every keyword in [interner], which must be empty, so that
  /// the ids match the constants above.
  static void seed(Interner interner) {
    assert(interner.length == 0, 'seed an empty interner');
    words.forEach(interner.internString);
  }
}
