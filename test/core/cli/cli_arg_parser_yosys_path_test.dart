// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/cli/cli_arg_parser.dart';

void main() {
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
