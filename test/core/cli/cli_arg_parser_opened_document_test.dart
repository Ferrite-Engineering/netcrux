// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/cli/cli_arg_parser.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';

/// A document macOS opens (a Finder double-click) is routed as that path
/// alone on the command line would be, so it reaches the same open flow —
/// and, for a project file, the same checks on its contents.
void main() {
  // No test here touches the file system: `/d/design` is a directory only
  // when this says so.
  final parser = CliArgParser(isDirectory: (path) => path == '/d/design');

  group('parseOpenedDocument', () {
    for (final (path, expected) in <(String, CliLaunchIntent)>[
      (
        '/d/demo.netcrux-project',
        const CliLaunchIntent.openProject('/d/demo.netcrux-project'),
      ),
      (
        '/d/Demo.NetCrux-Project',
        const CliLaunchIntent.openProject('/d/Demo.NetCrux-Project'),
      ),
      (
        '/d/review.netcrux',
        const CliLaunchIntent.openProject('/d/review.netcrux'),
      ),
      (
        '/d/uart.crux-project',
        const CliLaunchIntent.openProject('/d/uart.crux-project'),
      ),
      ('/d/design', const CliLaunchIntent.openProject('/d/design')),
      (
        '/d/team.netcrux-workspace',
        const CliLaunchIntent.openWorkspace('/d/team.netcrux-workspace'),
      ),
      (
        '/d/top.sv',
        const CliLaunchIntent.openSourceFiles(<String>['/d/top.sv']),
      ),
      (
        '/d/files.f',
        const CliLaunchIntent.openSourceFiles(<String>['/d/files.f']),
      ),
    ]) {
      test('$path opens as ${expected.runtimeType}', () {
        expect(parser.parseOpenedDocument(path), expected);
      });
    }

    test('agrees with the same path alone on the command line', () {
      for (final path in <String>[
        '/d/demo.netcrux-project',
        '/d/review.netcrux',
        '/d/uart.crux-project',
        '/d/design',
        '/d/top.sv',
      ]) {
        expect(
          parser.parseOpenedDocument(path),
          parser.parse(<String>[path]),
          reason: path,
        );
      }
    });

    test('never reads a flag out of the path', () {
      expect(
        parser.parseOpenedDocument('--workspace'),
        const CliLaunchIntent.openSourceFiles(<String>['--workspace']),
      );
    });
  });

  group('parseLaunch', () {
    test('with no arguments, opens the document macOS launched with', () async {
      final intent = await parser.parseLaunch(
        const <String>[],
        openedDocument: () async => '/d/demo.netcrux-project',
      );
      expect(
        intent,
        const CliLaunchIntent.openProject('/d/demo.netcrux-project'),
      );
    });

    test('with no arguments and no document, launches empty', () async {
      for (final document in <String?>[null, '']) {
        final intent = await parser.parseLaunch(
          const <String>['--reset-telemetry-consent'],
          openedDocument: () async => document,
        );
        expect(intent, const CliLaunchIntent.empty());
      }
    });

    test('an argument wins, and the document is not asked for', () async {
      var asked = false;
      final intent = await parser.parseLaunch(
        const <String>['/d/top.sv'],
        openedDocument: () async {
          asked = true;
          return '/d/demo.netcrux-project';
        },
      );
      expect(
        intent,
        const CliLaunchIntent.openSourceFiles(<String>['/d/top.sv']),
      );
      // Left with the runner, which delivers it once the workspace listens.
      expect(asked, isFalse);
    });
  });
}
