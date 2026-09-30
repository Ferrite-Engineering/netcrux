// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/cli/cli_arg_parser.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';

void main() {
  const parser = CliArgParser();

  group('CliArgParser', () {
    test('no args → empty intent', () {
      expect(parser.parse(const []), const CliLaunchIntent.empty());
    });

    test('single .netcrux arg → openProject', () {
      expect(
        parser.parse(const ['/tmp/projects/demo.netcrux']),
        const CliLaunchIntent.openProject('/tmp/projects/demo.netcrux'),
      );
    });

    test('single .netcrux-project arg → openProject', () {
      // `p.extension` returns the whole `.netcrux-project` suffix, so a
      // bare equality test against `.netcrux` misses the canonical project
      // extension and routes it to openSourceFiles, where the project JSON
      // is handed to Yosys as if it were HDL.
      expect(
        parser.parse(const ['examples/adder4/adder4.netcrux-project']),
        const CliLaunchIntent.openProject(
          'examples/adder4/adder4.netcrux-project',
        ),
      );
    });

    test('case-insensitive .netcrux-project extension is recognized', () {
      expect(
        parser.parse(const ['/tmp/projects/Demo.NetCrux-Project']),
        const CliLaunchIntent.openProject('/tmp/projects/Demo.NetCrux-Project'),
      );
    });

    test('case-insensitive .netcrux extension is recognized', () {
      expect(
        parser.parse(const ['/tmp/projects/demo.NetCrux']),
        const CliLaunchIntent.openProject('/tmp/projects/demo.NetCrux'),
      );
    });

    test('a positional <design>.crux-project manifest → openProject', () {
      expect(
        parser.parse(const ['/d/uart/uart.crux-project']),
        const CliLaunchIntent.openProject('/d/uart/uart.crux-project'),
      );
    });

    test('the manifest extension matches without regard to case', () {
      expect(
        parser.parse(const ['/d/uart/UART.Crux-Project']),
        const CliLaunchIntent.openProject('/d/uart/UART.Crux-Project'),
      );
    });

    test('a positional legacy bare .crux-project → openProject', () {
      // Its basename is `.crux-project`, whose `p.extension` is empty —
      // matching by extension alone sent it to Yosys as a source.
      expect(
        parser.parse(const ['/d/uart/.crux-project']),
        const CliLaunchIntent.openProject('/d/uart/.crux-project'),
      );
    });

    test('a name that only contains the manifest extension is a source', () {
      expect(
        parser.parse(const ['/d/notes.crux-project.txt']),
        const CliLaunchIntent.openSourceFiles(['/d/notes.crux-project.txt']),
      );
    });

    test('a positional directory → openProject, to find its manifest', () {
      final dirParser = CliArgParser(isDirectory: (path) => path == '/d/uart');
      expect(
        dirParser.parse(const ['/d/uart']),
        const CliLaunchIntent.openProject('/d/uart'),
      );
    });

    test('a directory among several positional args stays a source list', () {
      final dirParser = CliArgParser(isDirectory: (path) => path == '/d/uart');
      expect(
        dirParser.parse(const ['/d/uart', 'top.v']),
        const CliLaunchIntent.openSourceFiles(['/d/uart', 'top.v']),
      );
    });

    test('a positional .json netlist opens as a source tab', () {
      expect(
        parser.parse(const ['/d/top.netlist.json']),
        const CliLaunchIntent.openSourceFiles(['/d/top.netlist.json']),
      );
    });

    test('single .v arg → openSourceFiles with one entry', () {
      expect(
        parser.parse(const ['top.v']),
        const CliLaunchIntent.openSourceFiles(['top.v']),
      );
    });

    test('multiple HDL source files → openSourceFiles preserves order', () {
      expect(
        parser.parse(const ['a.v', 'b.sv', 'c.vhd']),
        const CliLaunchIntent.openSourceFiles(['a.v', 'b.sv', 'c.vhd']),
      );
    });

    test('two project files → falls back to openSourceFiles semantics', () {
      // Multiple positional args, none are recognised as the lone-project
      // shape, so the parser hands them to the source-files intent. The
      // downstream open path is responsible for rejecting non-source
      // extensions when it tries to elaborate.
      expect(
        parser.parse(const ['one.netcrux', 'two.netcrux']),
        const CliLaunchIntent.openSourceFiles(['one.netcrux', 'two.netcrux']),
      );
    });

    test('--flag value pairs are stripped', () {
      expect(
        parser.parse(const ['--yosys-path', '/opt/yosys/bin/yosys', 'top.v']),
        const CliLaunchIntent.openSourceFiles(['top.v']),
      );
    });

    test('--flag=value forms are stripped', () {
      expect(
        parser.parse(const ['--yosys-path=/opt/yosys/bin/yosys', 'top.v']),
        const CliLaunchIntent.openSourceFiles(['top.v']),
      );
    });

    test('bare short flags are stripped', () {
      expect(
        parser.parse(const ['-v', 'top.v']),
        const CliLaunchIntent.openSourceFiles(['top.v']),
      );
    });

    test('a sole flag with no value leaves no positional args', () {
      expect(parser.parse(const ['--help']), const CliLaunchIntent.empty());
    });

    // Only --workspace, --session and --yosys-path take a value. Any other
    // flag stands alone, so the file after it still opens.
    for (final flag in const [
      '--reset-telemetry-consent',
      '--reset-eula',
      '--unknown-flag',
    ]) {
      test('$flag does not take the file after it as its value', () {
        expect(
          parser.parse([flag, 'top.v']),
          const CliLaunchIntent.openSourceFiles(['top.v']),
        );
      });
    }
  });

  group('CliLaunchIntent equality', () {
    test('empty cases compare equal', () {
      expect(const CliLaunchIntent.empty(), const CliLaunchIntent.empty());
    });

    test('openProject equality is by path', () {
      expect(
        const CliLaunchIntent.openProject('a'),
        const CliLaunchIntent.openProject('a'),
      );
      expect(
        const CliLaunchIntent.openProject('a'),
        isNot(const CliLaunchIntent.openProject('b')),
      );
    });

    test('openSourceFiles equality is element-wise', () {
      expect(
        const CliLaunchIntent.openSourceFiles(['a', 'b']),
        const CliLaunchIntent.openSourceFiles(['a', 'b']),
      );
      expect(
        const CliLaunchIntent.openSourceFiles(['a', 'b']),
        isNot(const CliLaunchIntent.openSourceFiles(['b', 'a'])),
      );
    });
  });
}
