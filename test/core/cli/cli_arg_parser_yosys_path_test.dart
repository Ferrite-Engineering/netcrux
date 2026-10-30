// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/cli/cli_arg_parser.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';

void main() {
  netlistReaderTests();
  group('CliArgParser.yosysPathOverride', () {
    const parser = CliArgParser();

    test('returns null when the flag is absent', () {
      expect(parser.yosysPathOverride(const <String>[]), isNull);
      expect(
        parser.yosysPathOverride(const <String>['cpu.v', 'alu.v']),
        isNull,
      );
    });

    test('reads the next-arg form', () {
      expect(
        parser.yosysPathOverride(
          const <String>['--yosys-path', '/usr/bin/yosys', 'cpu.v'],
        ),
        '/usr/bin/yosys',
      );
    });

    test('reads the equals form', () {
      expect(
        parser.yosysPathOverride(
          const <String>['--yosys-path=/opt/yosys/bin/yosys'],
        ),
        '/opt/yosys/bin/yosys',
      );
    });

    test('returns null when the next arg is missing', () {
      expect(
        parser.yosysPathOverride(const <String>['--yosys-path']),
        isNull,
      );
    });

    test('returns null when the equals form is empty', () {
      expect(
        parser.yosysPathOverride(const <String>['--yosys-path=']),
        isNull,
      );
    });

    test('parser still routes positional file args correctly', () {
      // The flag and its value are stripped from the launch intent.
      final intent = parser.parse(
        const <String>['--yosys-path', '/usr/bin/yosys', 'cpu.v', 'alu.v'],
      );
      // openSourceFiles intent; the flag pair does not bleed into paths.
      expect(intent.runtimeType.toString(), 'OpenSourceFilesCliLaunch');
    });
  });
}

void netlistReaderTests() {
  group('CliArgParser.netlistReaderOverride', () {
    const parser = CliArgParser();

    test('reads the next-arg and equals forms', () {
      expect(
        parser.netlistReaderOverride(const <String>[
          '--netlist-reader',
          'yosys',
        ]),
        'yosys',
      );
      expect(
        parser.netlistReaderOverride(const <String>['--netlist-reader=native']),
        'native',
      );
    });

    test('is null when absent, empty or missing its value', () {
      expect(parser.netlistReaderOverride(const <String>['top.v']), isNull);
      expect(
        parser.netlistReaderOverride(const <String>['--netlist-reader=']),
        isNull,
      );
      expect(
        parser.netlistReaderOverride(const <String>['--netlist-reader']),
        isNull,
      );
    });

    test('the value is not opened as a source file', () {
      final intent = parser.parse(
        const <String>['--netlist-reader', 'yosys', 'top.v'],
      );
      expect(
        intent,
        isA<OpenSourceFilesCliLaunch>().having(
          (i) => i.paths,
          'paths',
          ['top.v'],
        ),
      );
      final eq = parser.parse(const <String>['--netlist-reader=native', 'a.v']);
      expect(
        eq,
        isA<OpenSourceFilesCliLaunch>().having((i) => i.paths, 'paths', [
          'a.v',
        ]),
      );
    });
  });
}
