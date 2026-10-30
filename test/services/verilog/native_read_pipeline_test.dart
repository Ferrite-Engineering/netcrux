// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/services/liberty/liberty_stub_service.dart';
import 'package:netcrux/services/verilog/native_read_pipeline.dart';
import 'package:path/path.dart' as p;

void main() {
  group('nativeReaderInapplicableReason', () {
    String? reason(NetcruxProject project) =>
        nativeReaderInapplicableReason(project);

    test('a Verilog project is eligible', () {
      expect(
        reason(NetcruxProject.create(sourceFiles: const ['/d/top.v'])),
        isNull,
      );
      expect(
        reason(NetcruxProject.create(sourceFiles: const ['/d/top.v.gz'])),
        isNull,
      );
    });

    test('no sources, extra Yosys commands and lowering are not', () {
      expect(reason(NetcruxProject.empty), contains('no source files'));
      expect(
        reason(
          NetcruxProject.create(
            sourceFiles: const ['/d/top.v'],
            extraYosysCommands: const ['flatten'],
          ),
        ),
        contains('extra Yosys commands'),
      );
      expect(
        reason(
          NetcruxProject.create(
            sourceFiles: const ['/d/top.v'],
            lowerToStructural: true,
          ),
        ),
        contains('lowers the design'),
      );
    });

    test('SystemVerilog, VHDL and an overridden language are not', () {
      expect(
        reason(NetcruxProject.create(sourceFiles: const ['/d/top.sv'])),
        contains('top.sv is not Verilog'),
      );
      expect(
        reason(NetcruxProject.create(sourceFiles: const ['/d/a.vhd'])),
        contains('a.vhd'),
      );
      expect(
        reason(
          NetcruxProject.create(
            sourceFiles: const ['/d/top.v'],
            sourceFileLanguages: const {
              '/d/top.v': NetcruxSourceLanguage.systemVerilog,
            },
          ),
        ),
        contains('top.v is not Verilog'),
      );
    });
  });

  group('attemptNativeRead', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('native_pipeline'));
    tearDown(() => dir.deleteSync(recursive: true));

    String write(String name, String text) {
      final path = p.join(dir.path, name);
      File(path).writeAsStringSync(text);
      return path;
    }

    LibertyStubService service() =>
        LibertyStubService(cacheBaseDirectory: () async => dir);

    test('reads through a Liberty library and reports its own lines', () async {
      final lib = write('cells.lib', '''
library (cells) {
  cell (INV) {
    pin (A) { direction : input ; }
    pin (Y) { direction : output ; }
  }
}
''');
      final top = write('top.v', '''
module top (input a, output y);
  INV u (.A(a), .Y(y), .VDD(a));
endmodule
''');
      final attempt = await attemptNativeRead(
        NetcruxProject.create(sourceFiles: [top], libertyFiles: [lib]),
        service(),
      );
      expect(attempt, isA<NativeAttemptRead>());
      final read = attempt as NativeAttemptRead;
      final cell = read.success.model.modules['top']!.cells['u']!;
      expect(cell.portDirections['A'], PortDirection.input);
      expect(cell.portDirections['Y'], PortDirection.output);
      // A pin the library lacks is inferred from the wiring and reported.
      expect(cell.portDirections['VDD'], PortDirection.input);
      final lines = read.diagnosticLines;
      expect(lines.first, startsWith('Info: Netlist read by the native'));
      expect(lines.join('\n'), contains('INV.VDD'));
    });

    test('a missing library is a warning, not a decline', () async {
      final top = write('top.v', 'module top (input a); endmodule\n');
      final attempt = await attemptNativeRead(
        NetcruxProject.create(
          sourceFiles: [top],
          libertyFiles: [p.join(dir.path, 'missing.lib')],
        ),
        service(),
      );
      expect(attempt, isA<NativeAttemptRead>());
      expect(
        (attempt as NativeAttemptRead).libraryWarnings.single,
        contains('missing.lib'),
      );
    });

    test('unsupported input declines with the construct and line', () async {
      final top = write(
        'top.v',
        'module top (input a);\n  initial a = 1;\nendmodule\n',
      );
      final attempt = await attemptNativeRead(
        NetcruxProject.create(sourceFiles: [top]),
        service(),
      );
      expect(attempt, isA<NativeAttemptDeclined>());
      final declined = (attempt as NativeAttemptDeclined).outcome;
      expect(declined.line, 2);
      expect(declined.diagnosticLine, contains('an `initial` block'));
      expect(declined.diagnosticLine, startsWith('$top:2: Warning:'));
    });

    test('a cancelled read is reported as cancelled', () async {
      final top = write('top.v', 'module top (input a); endmodule\n');
      final attempt = await attemptNativeRead(
        NetcruxProject.create(sourceFiles: [top]),
        service(),
        cancelSignal: Future<void>.value(),
      );
      expect(attempt, isA<NativeAttemptCancelled>());
    });
  });

  test('the Info line states size, top module and that Yosys was not run', () {
    expect(yosysReadInfoLine('why'), 'Info: Netlist read by Yosys (why).');
  });
}
