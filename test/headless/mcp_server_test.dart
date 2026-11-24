// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `netcrux mcp`: the definitions it lists, their budget, the instructions it
// gives, and the paths it refuses before anything is read or run.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/headless/cli_version.dart';
import 'package:netcrux/headless/net_design.dart';
import 'package:netcrux/headless/netcrux_cli.dart';
import 'package:path/path.dart' as p;

import 'support/fake_elaborator.dart';

/// The definitions the suite's tool contracts give the three tools.
const List<Map<String, Object?>> _contractDefinitions = <Map<String, Object?>>[
  <String, Object?>{
    'name': 'info',
    'description':
        'Elaborate a design and return its top module, hierarchy and cell and '
        'net counts.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'design': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
          'description':
              'Source files, one Yosys JSON netlist, or one .crux-project.',
        },
        'top': <String, Object?>{'type': 'string'},
      },
      'required': <String>['design'],
    },
  },
  <String, Object?>{
    'name': 'search',
    'description':
        'Find cells, nets, ports or modules by name in an elaborated design. '
        'Each hit carries its source line.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'design': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
          'description':
              'Source files, one Yosys JSON netlist, or one .crux-project.',
        },
        'top': <String, Object?>{'type': 'string'},
        'query': <String, Object?>{'type': 'string'},
        'kind': <String, Object?>{
          'type': 'string',
          'enum': <String>['cell', 'net', 'port', 'module'],
        },
        'glob': <String, Object?>{'type': 'boolean'},
        'limit': <String, Object?>{
          'type': 'integer',
          'description': 'Default 50, at most 500.',
        },
      },
      'required': <String>['design', 'query'],
    },
  },
  <String, Object?>{
    'name': 'connections',
    'description':
        'One step of connectivity within a module: for a cell, its pins and '
        'the net on each; for a net, the pins that drive it and the pins it '
        'drives.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'design': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
          'description':
              'Source files, one Yosys JSON netlist, or one .crux-project.',
        },
        'top': <String, Object?>{'type': 'string'},
        'name': <String, Object?>{
          'type': 'string',
          'description': 'Hierarchical cell or net name.',
        },
      },
      'required': <String>['design', 'name'],
    },
  },
];

void main() {
  final fixtures = p.absolute('spec', 'fixtures');

  NetCruxCli cli(FakeElaborator yosys) => NetCruxCli(
    reader: NetDesignReader(elaborator: yosys),
    telemetry: () => null,
  );

  Future<Map<String, Object?>> call(
    NetCruxCli cli,
    String root,
    String tool,
    Map<String, Object?> arguments,
  ) async {
    final line = await cli
        .server(root: root)
        .handleLine(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': <String, Object?>{'name': tool, 'arguments': arguments},
          }),
        );
    final result =
        (jsonDecode(line!) as Map<String, Object?>)['result']!
            as Map<String, Object?>;
    final text =
        ((result['content']! as List<Object?>).single!
                as Map<String, Object?>)['text']!
            as String;
    return jsonDecode(text) as Map<String, Object?>;
  }

  group('definitions', () {
    test("are the contracts' text, in listing order", () {
      final server = cli(FakeElaborator.failing()).server(root: fixtures);
      expect(
        jsonEncode(server.definitions()),
        jsonEncode(_contractDefinitions),
      );
    });

    test('keep the budget: 2,000 a tool, 4,000 the server', () {
      final server = cli(FakeElaborator.failing()).server(root: fixtures);
      expectDefinitionBudget(server);
      final sizes = <String, int>{
        for (final t in server.tools) t.name: t.definitionLength,
      };
      // Measured; the suite's definition budget records these sizes.
      expect(sizes, <String, int>{
        'info': 333,
        'search': 547,
        'connections': 480,
      });
      expect(kNetCruxMcpInstructions.length, 515);
    });

    test('the open-core binary lists only the free tools', () {
      final names = cli(
        FakeElaborator.failing(),
      ).commands.map((c) => c.tool.name);
      expect(names, <String>['info', 'search', 'connections']);
    });
  });

  group('initialize', () {
    test('names the program and gives the instructions', () async {
      final server = cli(FakeElaborator.failing()).server(root: fixtures);
      final line = await server.handleLine(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': <String, Object?>{'protocolVersion': '2025-06-18'},
        }),
      );
      final result =
          (jsonDecode(line!) as Map<String, Object?>)['result']!
              as Map<String, Object?>;
      expect(result['serverInfo'], <String, Object?>{
        'name': 'netcrux',
        'version': kNetCruxCliVersion,
      });
      expect(result['instructions'], kNetCruxMcpInstructions);
    });

    test('the instructions claim no lift and carry no em dash', () {
      expect(kNetCruxMcpInstructions, isNot(contains('\u2014')));
      for (final word in <String>['better', 'faster', 'improve', 'honest']) {
        expect(kNetCruxMcpInstructions.toLowerCase(), isNot(contains(word)));
      }
    });
  });

  group('confinement: refused, and nothing read or run', () {
    late Directory outside;

    setUp(() {
      outside = Directory.systemTemp.createTempSync('netcrux_mcp_outside_');
    });

    tearDown(() => outside.deleteSync(recursive: true));

    Future<void> refused(
      Map<String, Object?> arguments, {
      String root = '',
      Matcher message = anything,
    }) async {
      final yosys = FakeElaborator.failing();
      final doc = await call(
        cli(yosys),
        root.isEmpty ? fixtures : root,
        'info',
        arguments,
      );
      expect(doc['outcome'], 'usage_error');
      final diagnostics = (doc['diagnostics']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(diagnostics.single['message'], message);
      expect(yosys.requests, isEmpty, reason: 'Yosys must not run');
    }

    test('a search kind outside the enum, in the command line words', () async {
      final yosys = FakeElaborator.failing();
      final doc = await call(cli(yosys), fixtures, 'search', <String, Object?>{
        'design': <String>['top.v'],
        'query': 'a',
        'kind': 'wire',
      });
      expect(doc['outcome'], 'usage_error');
      final diagnostics = (doc['diagnostics']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        diagnostics.single['message'],
        '`--kind wire` is not cell, net, port or module',
      );
      expect(yosys.requests, isEmpty, reason: 'Yosys must not run');
    });

    test('a path outside the root', () async {
      await refused(<String, Object?>{
        'design': <String>[p.join(outside.path, 'top.v')],
      }, message: contains('outside the root'));
    });

    test('a symbolic link that leads out', () async {
      final target = File(p.join(outside.path, 'top.v'))
        ..writeAsStringSync('module top; endmodule\n');
      final root = Directory.systemTemp.createTempSync('netcrux_mcp_root_');
      addTearDown(() => root.deleteSync(recursive: true));
      Link(p.join(root.path, 'top.v')).createSync(target.path);
      await refused(<String, Object?>{
        'design': <String>['top.v'],
      }, root: root.path);
    });

    test('a Windows network path, on its spelling', () async {
      await refused(<String, Object?>{
        'design': <String>[r'\\server\share\top.v'],
      }, message: contains('network or device path'));
    });

    test('a filelist that names a source outside', () async {
      await refused(<String, Object?>{
        'design': <String>['escape.f'],
      }, message: contains('outside the root'));
    });

    test('a filelist that names a filelist outside, which is never '
        'opened', () async {
      final doc = await call(
        cli(FakeElaborator.failing()),
        fixtures,
        'info',
        <String, Object?>{
          'design': <String>['escape_nested.f'],
        },
      );
      expect(doc['outcome'], 'usage_error');
      final message =
          ((doc['diagnostics']! as List<Object?>).single!
                  as Map<String, Object?>)['message']!
              as String;
      // The nested filelist itself is refused: it was judged before any
      // read, so its (absent) contents never mattered.
      expect(message, contains(p.join(p.dirname(fixtures), 'outside.f')));
    });

    test('a manifest that names a netlist outside', () async {
      final root = Directory.systemTemp.createTempSync('netcrux_mcp_root_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(
        p.join(outside.path, 'n.json'),
      ).writeAsStringSync(
        File(p.join(fixtures, 'counter.json')).readAsStringSync(),
      );
      File(p.join(root.path, 'd.crux-project')).writeAsStringSync(
        'version: 1\nartifacts:\n  netlist: ${p.join(outside.path, 'n.json')}\n',
      );
      await refused(
        <String, Object?>{
          'design': <String>['d.crux-project'],
        },
        root: root.path,
        message: contains('outside the root'),
      );
    });

    test('a manifest that names sources outside', () async {
      final root = Directory.systemTemp.createTempSync('netcrux_mcp_root_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(
        p.join(outside.path, 'a.v'),
      ).writeAsStringSync('module a; endmodule\n');
      File(p.join(root.path, 'd.crux-project')).writeAsStringSync(
        'version: 1\ndesign:\n  sources:\n    - ${p.join(outside.path, 'a.v')}\n',
      );
      await refused(
        <String, Object?>{
          'design': <String>['d.crux-project'],
        },
        root: root.path,
        message: contains('outside the root'),
      );
    });
  });

  test('a design inside the root is read', () async {
    final doc = await call(
      cli(FakeElaborator.writing(p.join(fixtures, 'counter.json'))),
      fixtures,
      'info',
      <String, Object?>{
        'design': <String>['design.f'],
      },
    );
    expect(doc['outcome'], 'completed');
  });
}
