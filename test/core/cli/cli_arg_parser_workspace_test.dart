// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/cli/cli_arg_parser.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';

void main() {
  group('CliArgParser — workspace flags', () {
    const parser = CliArgParser();

    test('--workspace wins over every other intent', () {
      final intent = parser.parse(<String>[
        '--workspace',
        '/d/team.netcrux-workspace',
        '--session',
        '/d/x.netcrux',
        '/d/y.v',
      ]);
      expect(intent, isA<OpenWorkspaceCliLaunch>());
      expect(
        (intent as OpenWorkspaceCliLaunch).path,
        '/d/team.netcrux-workspace',
      );
    });

    test('--session wins over positional args', () {
      final intent = parser.parse(<String>[
        '--session',
        '/d/x.netcrux',
        '/d/y.v',
      ]);
      expect(intent, isA<OpenSessionCliLaunch>());
      expect((intent as OpenSessionCliLaunch).path, '/d/x.netcrux');
    });

    test('--session accepts the equals form', () {
      final intent = parser.parse(<String>['--session=/d/x.netcrux']);
      expect(intent, isA<OpenSessionCliLaunch>());
      expect((intent as OpenSessionCliLaunch).path, '/d/x.netcrux');
    });

    test('--workspace accepts the equals form', () {
      final intent = parser.parse(<String>[
        '--workspace=/d/x.netcrux-workspace',
      ]);
      expect(intent, isA<OpenWorkspaceCliLaunch>());
    });

    test('multiple positional source files → OpenSourceFilesCliLaunch '
        '(WorkspaceScreen opens each as a separate tab)', () {
      final intent = parser.parse(<String>['/d/a.v', '/d/b.sv', '/d/c.vhd']);
      expect(intent, isA<OpenSourceFilesCliLaunch>());
      expect(
        (intent as OpenSourceFilesCliLaunch).paths,
        ['/d/a.v', '/d/b.sv', '/d/c.vhd'],
      );
    });

    test('one .netcrux-project positional → OpenProjectCliLaunch', () {
      final intent = parser.parse(<String>['/d/proj.netcrux']);
      expect(intent, isA<OpenProjectCliLaunch>());
    });

    test('no args → EmptyCliLaunch', () {
      final intent = parser.parse(const <String>[]);
      expect(intent, isA<EmptyCliLaunch>());
    });

    test('sessionPathOverride / workspacePathOverride extract values', () {
      expect(
        parser.sessionPathOverride(<String>['--session', '/d/x.netcrux']),
        '/d/x.netcrux',
      );
      expect(
        parser.workspacePathOverride(<String>[
          '--workspace=foo.netcrux-workspace',
        ]),
        'foo.netcrux-workspace',
      );
      expect(parser.sessionPathOverride(<String>['--other']), isNull);
    });
  });
}
