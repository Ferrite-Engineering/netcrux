// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:path/path.dart' as p;

const LibertyPortDirection _in = LibertyPortDirection.input;
const LibertyPortDirection _out = LibertyPortDirection.output;
const LibertyPortDirection _io = LibertyPortDirection.inout;

LibertyPort _port(
  String name,
  LibertyPortDirection dir, [
  int? msb,
  int? lsb,
]) => LibertyPort(name: name, direction: dir, msb: msb, lsb: lsb);

/// A small library with the shapes a real standard-cell file has: power
/// pins first, timing tables inside pins, a bus through a library type,
/// and a test_cell whose pins must not leak into the cell.
const String _stdcells = r'''
/* A tiny cell library.
   Block comment over two lines. */
library (tiny) {
  delay_model : table_lookup ;
  capacitive_load_unit (1, pf) ;
  lu_table_template (delay_3x3) {
    variable_1 : input_net_transition ;
    index_1 ("0.1, 0.2, 0.3") ;
  }
  type (bus4) {
    base_type : array ;
    data_type : bit ;
    bit_width : 4 ;
    bit_from : 3 ;
    bit_to : 0 ;
    downto : true ;
  }
  cell (INVX1) {
    area : 1.5 ;
    pg_pin (VDD) { voltage_name : VDD ; pg_type : primary_power ; }
    pg_pin (VSS) { voltage_name : VSS ; pg_type : primary_ground ; }
    pin (A) {
      direction : input ;
      capacitance : 0.002 ;
    }
    pin (Y) {
      direction : output ;
      function : "!A" ;
      timing () {
        related_pin : "A" ;
        cell_rise (delay_3x3) {
          values ("0.1, 0.2, 0.3", \
                  "0.4, 0.5, 0.6", \
                  "0.7, 0.8, 0.9") ;
        }
      }
      internal_power () { related_pin : "A" ; }
    }
  }
  cell (DFF4) {
    pin (CK) { direction : input ; clock : true ; }
    bus (D) {
      bus_type : bus4 ;
      direction : input ;
      pin (D[0]) { timing () { related_pin : "CK" ; } }
    }
    bus (Q) {
      bus_type : bus4 ;
      direction : output ;
    }
    pin (IQ) { direction : internal ; }
    ff (IQ, IQN) { clocked_on : "CK" ; next_state : "D" ; }
    test_cell () {
      pin (SI) { direction : input ; signal_type : test_scan_in ; }
    }
  }
}
''';

void main() {
  group('LibertyParser', () {
    test('reads pins, pg_pins and buses through a library type', () {
      final lib = LibertyParser.parseString(_stdcells, path: 'tiny.lib');
      expect(lib.cells.map((c) => c.name), <String>['INVX1', 'DFF4']);
      expect(lib.cells[0].ports, <LibertyPort>[
        _port('VDD', _io),
        _port('VSS', _io),
        _port('A', _in),
        _port('Y', _out),
      ]);
      // The internal pin and the test_cell's scan pin are not ports.
      expect(lib.cells[1].ports, <LibertyPort>[
        _port('CK', _in),
        _port('D', _in, 3, 0),
        _port('Q', _out, 3, 0),
      ]);
      expect(lib.warnings, isEmpty);
    });

    test('a pin group naming several pins declares each of them', () {
      final lib = LibertyParser.parseString('''
library (l) {
  cell (NAND3) {
    pin (A, B, "C") { direction : input ; }
    pin (Y) { direction : output ; }
  }
}
''');
      expect(lib.cells.single.ports, <LibertyPort>[
        _port('A', _in),
        _port('B', _in),
        _port('C', _in),
        _port('Y', _out),
      ]);
    });

    test('quoted and unusual names come back without their quotes', () {
      final lib = LibertyParser.parseString(r'''
library ("l") {
  cell ("AND2$X") {
    pin ("A[0]") { direction : input ; }
    pin (B.1) { direction : input ; }
    pin (Z) { direction : output }
  }
}
''');
      final cell = lib.cells.single;
      expect(cell.name, r'AND2$X');
      expect(cell.ports.map((p) => p.name), <String>['A[0]', 'B.1', 'Z']);
      // `direction : output` without its semicolon still reads.
      expect(cell.ports.last.direction, _out);
    });

    test('a cell-level type shadows the library type of the same name', () {
      final lib = LibertyParser.parseString('''
library (l) {
  type (bus) { bit_from : 7 ; bit_to : 0 ; bit_width : 8 ; }
  cell (A) {
    type (bus) { bit_from : 0 ; bit_to : 1 ; bit_width : 2 ; }
    bus (X) { bus_type : bus ; direction : input ; }
  }
  cell (B) {
    bus (X) { bus_type : "bus" ; direction : output ; }
  }
}
''');
      expect(lib.cells[0].ports.single, _port('X', _in, 0, 1));
      expect(lib.cells[1].ports.single, _port('X', _out, 7, 0));
    });

    test('a type with only a width gives an ascending or descending range', () {
      final lib = LibertyParser.parseString('''
library (l) {
  type (up) { bit_width : 3 ; }
  type (down) { bit_width : 3 ; downto : true ; }
  cell (C) {
    bus (U) { bus_type : up ; direction : input ; }
    bus (D) { bus_type : down ; direction : input ; }
  }
}
''');
      expect(lib.cells.single.ports, <LibertyPort>[
        _port('U', _in, 0, 2),
        _port('D', _in, 2, 0),
      ]);
    });

    test('a bus without a usable type takes its range from its pins', () {
      final lib = LibertyParser.parseString('''
library (l) {
  cell (C) {
    bus (D) {
      bus_type : missing ;
      pin (D[1:2]) { direction : input ; }
      pin (D[0]) { direction : input ; }
    }
    bus (E) { direction : input ; }
  }
}
''');
      final ports = lib.cells.single.ports;
      // Direction comes from the member pins when the bus has none.
      expect(ports[0], _port('D', _in, 2, 0));
      expect(ports[1], _port('E', _in));
      expect(lib.warnings.single, contains('"E"'));
    });

    test('bundle members become scalar ports', () {
      final lib = LibertyParser.parseString('''
library (l) {
  cell (MB) {
    bundle (Q) {
      members (Q0, Q1) ;
      direction : output ;
      pin (Q1) { direction : inout ; }
    }
  }
}
''');
      expect(lib.cells.single.ports, <LibertyPort>[
        _port('Q0', _out),
        _port('Q1', _io),
      ]);
    });

    test('comments, continuations and braces inside strings are skipped', () {
      final lib = LibertyParser.parseString(r'''
// A line comment at the top.
library (l) { // trailing comment
  comment : "a { brace } in a string" ;
  cell (BUF) /* comment between name and body */ {
    pin (A) { direction /* here too */ : input ; }
    pin (Y) {
      direction : \
        output ;
      timing () {
        when : "A}" ;
        /* } a brace in a comment */
        values ("1, 2", \
                "3, 4") ;
      }
    }
  }
}
''');
      expect(lib.cells.single.ports, <LibertyPort>[
        _port('A', _in),
        _port('Y', _out),
      ]);
    });

    test(
      'a cell declared twice in one file keeps the first, with a warning',
      () {
        final lib = LibertyParser.parseString('''
library (l) {
  cell (X) { pin (A) { direction : input ; } }
  cell (X) { pin (B) { direction : input ; } }
}
''');
        expect(lib.cells.single.ports.single.name, 'A');
        expect(lib.warnings.single, contains('"X"'));
      },
    );

    test('a missing direction is inout and an internal pin is dropped', () {
      final lib = LibertyParser.parseString('''
library (l) {
  cell (X) {
    pin (A) { capacitance : 1 ; }
    pin (I) { direction : internal ; }
  }
}
''');
      expect(lib.cells.single.ports, <LibertyPort>[_port('A', _io)]);
    });

    group('malformed input', () {
      void expectError(String text, Matcher message, {int? line}) {
        expect(
          () => LibertyParser.parseString(text, path: 'bad.lib'),
          throwsA(
            isA<LibertyParseException>()
                .having((e) => e.path, 'path', 'bad.lib')
                .having((e) => e.message, 'message', message)
                .having((e) => e.line, 'line', line ?? anything),
          ),
        );
      }

      test('an unclosed library group', () {
        expectError(
          'library (l) {\n  cell (X) {\n    pin (A) { direction : input ; }\n',
          contains('never closed'),
        );
      });

      test('an unclosed table inside a skipped group', () {
        expectError(
          'library (l) {\n cell (X) {\n  pin (A) {\n   timing () {\n',
          contains('timing group that starts on line 4 is never closed'),
        );
      });

      test('an unterminated string', () {
        expectError(
          'library (l) {\n  comment : "oops ;\n}\n',
          contains('string that starts on line 2'),
        );
      });

      test('an unterminated comment', () {
        expectError('library (l) { /* no end', contains('comment'));
      });

      test('a statement that is neither attribute nor group', () {
        expectError(
          'library (l) {\n  cell X { }\n}\n',
          contains('expected ":" or "("'),
          line: 2,
        );
      });

      test('not a Liberty file at all', () {
        expectError('module top; endmodule\n', anything);
        expectError('', contains('no library'));
      });

      test('the description names the file and the line', () {
        try {
          LibertyParser.parseString('library (l) {\n  cell X\n', path: 'x.lib');
          fail('expected a parse error');
        } on LibertyParseException catch (e) {
          expect(e.description, startsWith('x.lib, line '));
        }
      });
    });

    group('parseFile', () {
      late Directory dir;
      setUp(() => dir = Directory.systemTemp.createTempSync('liberty_test'));
      tearDown(() => dir.deleteSync(recursive: true));

      test('matches parseString at every buffer size', () {
        final path = p.join(dir.path, 'tiny.lib');
        File(path).writeAsStringSync(_stdcells);
        final expected = LibertyParser.parseString(_stdcells, path: path);
        // Small buffers put every token, comment, string and continuation
        // across a refill boundary somewhere.
        for (var size = 1; size <= 17; size++) {
          final lib = LibertyParser.parseFile(path, bufferSize: size);
          expect(
            lib.toJson(),
            expected.toJson(),
            reason: 'buffer size $size',
          );
        }
      });

      test('a file that does not exist is a parse error naming it', () {
        final path = p.join(dir.path, 'missing.lib');
        expect(
          () => LibertyParser.parseFile(path),
          throwsA(
            isA<LibertyParseException>().having((e) => e.path, 'path', path),
          ),
        );
      });

      test('skips a large timing table without trouble', () {
        final rows = List<String>.filled(20000, '"0.1, 0.2, 0.3, 0.4"');
        final text =
            '''
library (big) {
  cell (X) {
    pin (A) { direction : input ; }
    pin (Y) {
      direction : output ;
      timing () { cell_rise (t) { values (${rows.join(', \\\n')}) ; } }
    }
  }
}
''';
        final path = p.join(dir.path, 'big.lib');
        File(path).writeAsStringSync(text);
        final lib = LibertyParser.parseFile(path, bufferSize: 4096);
        expect(lib.cells.single.ports.map((p) => p.name), <String>['A', 'Y']);
      });
    });
    group('gzip-compressed files', () {
      const plain = 'test/fixtures/liberty/cells.lib';
      const gzipped = 'test/fixtures/liberty/cells.lib.gz';
      late Directory dir;
      setUp(() => dir = Directory.systemTemp.createTempSync('liberty_gz'));
      tearDown(() => dir.deleteSync(recursive: true));

      /// What was read, without the path it was read from.
      Map<String, Object?> cellsOf(String path, {int? bufferSize}) {
        final json = bufferSize == null
            ? LibertyParser.parseFile(path).toJson()
            : LibertyParser.parseFile(path, bufferSize: bufferSize).toJson();
        return <String, Object?>{...json}..remove('path');
      }

      test('a .lib.gz made by gzip reads as the plain file does', () {
        final expected = cellsOf(plain);
        expect(
          (expected['cells']! as List<Object?>).length,
          2,
          reason: 'the fixture has two cells',
        );
        // Small buffers put the decompressed stream across refill
        // boundaries everywhere; the default is what the app uses.
        for (final size in <int>[1, 2, 3, 7, 64, 4096, 1 << 20]) {
          expect(
            cellsOf(gzipped, bufferSize: size),
            expected,
            reason: 'buffer size $size',
          );
        }
      });

      test('a compressed library of many blocks reads like its plain twin', () {
        // Random-looking numbers do not compress, so the compressed file is
        // many times the 64 KiB block the reader inflates at a time, and
        // one table straddles several of them.
        final random = Random(7);
        String number() => random.nextDouble().toString();
        final rows = <String>[
          for (var i = 0; i < 40000; i++)
            '"${number()}, ${number()}, ${number()}"',
        ];
        final text =
            '''
library (big) {
  cell (X) {
    pin (A) { direction : input ; }
    pin (Y) {
      direction : output ;
      timing () { cell_rise (t) { values (${rows.join(', \\\n')}) ; } }
    }
  }
  cell (Z) { pin (Q) { direction : output ; } }
}
''';
        final path = p.join(dir.path, 'big.lib.gz');
        File(path).writeAsBytesSync(gzip.encode(utf8.encode(text)));
        expect(
          File(path).lengthSync(),
          greaterThan(5 * (1 << 16)),
          reason: 'the test needs a compressed file of several blocks',
        );
        final expected = LibertyParser.parseString(text, path: path).toJson();
        expect(LibertyParser.parseFile(path).toJson(), expected);
        expect(
          LibertyParser.parseFile(path, bufferSize: 4096).toJson(),
          expected,
        );
      });

      test('the content decides, not the name', () {
        final expected = cellsOf(plain);
        final misnamedGzip = p.join(dir.path, 'compressed.lib');
        File(gzipped).copySync(misnamedGzip);
        expect(cellsOf(misnamedGzip), expected);
        final misnamedText = p.join(dir.path, 'text.lib.gz');
        File(plain).copySync(misnamedText);
        expect(cellsOf(misnamedText), expected);
      });

      test('a truncated file is a parse error naming it', () {
        final bytes = File(gzipped).readAsBytesSync();
        final path = p.join(dir.path, 'cut.lib.gz');
        File(path).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
        expect(
          () => LibertyParser.parseFile(path),
          throwsA(
            isA<LibertyParseException>().having((e) => e.path, 'path', path),
          ),
        );
      });

      test('corrupt compressed data is a parse error naming the file', () {
        final bytes = File(gzipped).readAsBytesSync().toList();
        for (var i = 30; i < bytes.length - 8; i++) {
          bytes[i] = bytes[i] ^ 0x5a;
        }
        final path = p.join(dir.path, 'bad.lib.gz');
        File(path).writeAsBytesSync(bytes);
        expect(
          () => LibertyParser.parseFile(path),
          throwsA(
            isA<LibertyParseException>()
                .having((e) => e.path, 'path', path)
                .having((e) => e.description, 'description', contains('gzip')),
          ),
        );
      });

      test('an empty .lib.gz is not a Liberty file', () {
        final path = p.join(dir.path, 'empty.lib.gz');
        File(path).writeAsBytesSync(gzip.encode(const <int>[]));
        expect(
          () => LibertyParser.parseFile(path),
          throwsA(isA<LibertyParseException>()),
        );
      });
    });
  });
}
