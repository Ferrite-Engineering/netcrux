// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/cli/cli_args.dart';

void main() {
  group('parseCliArgs', () {
    test('defaults: reset and noRestore are false', () {
      final cli = parseCliArgs(const []);
      expect(cli.reset, isFalse);
      expect(cli.noRestore, isFalse);
    });

    test('--reset sets reset', () {
      final cli = parseCliArgs(const ['--reset']);
      expect(cli.reset, isTrue);
      expect(cli.noRestore, isFalse);
    });

    test('--no-restore sets noRestore', () {
      final cli = parseCliArgs(const ['--no-restore']);
      expect(cli.noRestore, isTrue);
      expect(cli.reset, isFalse);
    });

    test('--reset and --no-restore compose with a positional file', () {
      final cli = parseCliArgs(const ['--reset', '--no-restore', 'top.v']);
      expect(cli.reset, isTrue);
      expect(cli.noRestore, isTrue);
    });

    test('unknown flags are silently ignored', () {
      final cli = parseCliArgs(const ['--foo', '--bar=baz', 'top.v']);
      expect(cli.reset, isFalse);
      expect(cli.noRestore, isFalse);
    });

    test('positional paths and primary-parser flags are ignored', () {
      final cli = parseCliArgs(const [
        'design.netcrux',
        '--workspace',
        'a.netcrux-workspace',
        '--yosys-path',
        '/usr/bin/yosys',
      ]);
      expect(cli.reset, isFalse);
      expect(cli.noRestore, isFalse);
    });
  });

  group('stripLaunchFlags', () {
    test('removes --reset and --no-restore, keeps everything else', () {
      expect(
        stripLaunchFlags(const ['--reset', '--no-restore', 'top.v', '--foo']),
        equals(['top.v', '--foo']),
      );
    });

    test('preserves positional following a launch flag', () {
      // The primary parser's flag-stripping heuristic treats `--reset top.v`
      // as a flag + value pair; stripping first keeps `top.v` positional.
      expect(
        stripLaunchFlags(const ['--reset', 'top.v']),
        equals(['top.v']),
      );
    });

    test('no-op on args without launch flags', () {
      expect(
        stripLaunchFlags(const ['a.sv', '--session', 's.netcrux']),
        equals(['a.sv', '--session', 's.netcrux']),
      );
    });
  });

  group('cliHelpText', () {
    test('mentions every supported flag', () {
      final help = cliHelpText();
      expect(help, contains('--workspace'));
      expect(help, contains('--session'));
      expect(help, contains('--yosys-path'));
      expect(help, contains('--no-restore'));
      expect(help, contains('--reset'));
      expect(help, contains('--reset-telemetry-consent'));
      expect(help, contains('--reset-eula'));
      expect(help, contains('--help'));
      expect(help, contains('netcrux'));
    });
  });
}
