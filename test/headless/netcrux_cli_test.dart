// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The `netcrux` command line around the documents: help, version, exit
// codes, the plain-text form, and the cases only the command line reaches.
// Values are worked by hand from `spec/fixtures/counter.json`.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/headless/cli_version.dart';
import 'package:netcrux/headless/net_design.dart';
import 'package:netcrux/headless/netcrux_cli.dart';
import 'package:path/path.dart' as p;

import 'support/fake_elaborator.dart';

void main() {
  final fixtures = p.absolute('spec', 'fixtures');
  final netlist = p.join(fixtures, 'counter.json');

  Future<(int, String, String)> run(
    List<String> argv, {
    FakeElaborator? yosys,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await NetCruxCli(
      reader: NetDesignReader(elaborator: yosys ?? FakeElaborator.failing()),
      telemetry: () => null,
    ).run(argv, out: out, err: err);
    return (code, out.toString(), err.toString());
  }

  Map<String, Object?> json(String text) =>
      jsonDecode(text) as Map<String, Object?>;

  test('--version names the program and its version', () async {
    final (code, out, _) = await run(<String>['--version']);
    expect(code, 0);
    expect(out, 'netcrux $kNetCruxCliVersion\n');
  });

  test('no arguments is a usage error with the help on stderr', () async {
    final (code, out, err) = await run(const <String>[]);
    expect(code, 64);
    expect(out, isEmpty);
    expect(err, contains('connections'));
    expect(err, contains('mcp'));
  });

  test('an unknown command is a usage error, and so is a Pro one', () async {
    for (final c in <String>['cone', 'trace-x', 'cdc']) {
      final (code, _, err) = await run(<String>[c, netlist]);
      expect(code, 64, reason: c);
      expect(err, contains('unknown command `$c`'));
    }
  });

  test('each command has --help', () async {
    for (final c in <String>['info', 'search', 'connections']) {
      final (code, out, _) = await run(<String>[c, '--help']);
      expect(code, 0, reason: c);
      expect(out, contains('Usage: netcrux $c'), reason: c);
      expect(out, contains('--json'), reason: c);
      expect(out, contains('--top'), reason: c);
    }
  });

  test('mcp refuses a root that is not a directory', () async {
    final (code, _, err) = await run(<String>['mcp', '--root', netlist]);
    expect(code, 64);
    expect(err, contains('is not a directory'));
  });

  test('mcp hands its --license-file to the commands and the counter, '
      'before the counter is made', () async {
    String? seenByTelemetry;
    late final NetCruxCli cli;
    cli = NetCruxCli(
      reader: NetDesignReader(elaborator: FakeElaborator.failing()),
      telemetry: () async {
        seenByTelemetry = cli.commandContext.licenseFile;
        return null;
      },
      instructions: 'Another edition.',
      licenseHelp: 'Read by another edition.',
    );
    final output = StreamController<List<int>>();
    final written = output.stream.toList();
    final out = StringBuffer();
    final code = await cli.run(
      <String>['mcp', '--root', fixtures, '--license-file', '/l.key'],
      out: out,
      err: StringBuffer(),
      input: const Stream<List<int>>.empty(),
      output: output.sink,
    );
    await output.close();
    await written;
    expect(code, 0);
    expect(seenByTelemetry, '/l.key');
    expect(cli.server(root: fixtures).instructions, 'Another edition.');
    await cli.run(<String>['mcp', '--help'], out: out, err: StringBuffer());
    expect(out.toString(), contains('Read by another edition.'));
  });

  test('the server answers over its streams, one line per reply', () async {
    final cli = NetCruxCli(
      reader: NetDesignReader(elaborator: FakeElaborator.failing()),
      telemetry: () => null,
    );
    final output = StreamController<List<int>>();
    final written = output.stream.transform(utf8.decoder).join();
    final requests = <Map<String, Object?>>[
      <String, Object?>{'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'info',
          'arguments': <String, Object?>{
            'design': <String>['counter.json'],
          },
        },
      },
    ];
    final code = await cli.run(
      <String>['mcp', '--root', fixtures],
      out: StringBuffer(),
      err: StringBuffer(),
      input: Stream<List<int>>.value(
        utf8.encode(requests.map((r) => '${jsonEncode(r)}\n').join()),
      ),
      output: output.sink,
    );
    await output.close();
    final lines = const LineSplitter().convert(await written);
    expect(code, 0);
    expect(lines, hasLength(2));
    final call = json(lines.last)['result']! as Map<String, Object?>;
    expect(call['isError'], isFalse);
  });

  test('a missing file exits 65 with its document', () async {
    final (code, out, _) = await run(<String>[
      'info',
      p.join(fixtures, 'missing.json'),
      '--json',
    ]);
    expect(code, 65);
    expect(json(out)['outcome'], 'input_error');
  });

  test('a Yosys failure exits 3 with its document', () async {
    final (code, out, err) = await run(<String>[
      'info',
      p.join(fixtures, 'top.v'),
      p.join(fixtures, 'inc.v'),
    ]);
    expect(code, 3);
    expect(out, isEmpty);
    expect(err, contains('error: Yosys stopped with exit code 1'));
  });

  test('without --json, a person reads the answer', () async {
    final (code, out, err) = await run(<String>['info', netlist]);
    expect(code, 0);
    expect(err, isEmpty);
    expect(
      out,
      'top top: 2 modules, 3 cells, 7 nets\n'
      '  top (top, 2 cells)\n'
      '  top.u_inc (inc, 1 cells)\n',
    );
    final (_, net, _) = await run(<String>['connections', netlist, 'top.n']);
    expect(
      net,
      'net top.n in top\n'
      '  driven by top.u_inc.y\n'
      '  drives top.q_reg.D\n',
    );
  });

  test('search --kind and --glob narrow the hits', () async {
    final (_, out, _) = await run(<String>[
      'search',
      netlist,
      '?',
      '--glob',
      '--kind',
      'port',
      '--json',
    ]);
    final body = json(out)['body']! as Map<String, Object?>;
    // Ports with one-character names: top's clk is not one; a and y of top
    // and of u_inc are.
    expect(
      (body['hits']! as List<Object?>).map(
        (h) => (h! as Map<String, Object?>)['path'],
      ),
      <String>['top.a', 'top.y', 'top.u_inc.a', 'top.u_inc.y'],
    );
    final (_, modules, _) = await run(<String>[
      'search',
      netlist,
      'INC',
      '--kind',
      'module',
      '--json',
    ]);
    final hit =
        ((json(modules)['body']! as Map<String, Object?>)['hits']!
                    as List<Object?>)
                .single!
            as Map<String, Object?>;
    expect(hit['path'], 'inc');
    expect(hit['location'], <String, Object?>{
      'file': 'inc.v',
      'line': 1,
      'column': 1,
    });
  });

  test('a NetCrux project file is refused for what it is', () async {
    final dir = Directory.systemTemp.createTempSync('netcrux_cli_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final project = File(p.join(dir.path, 'd.netcrux-project'))
      ..writeAsStringSync('{}');
    final (code, out, _) = await run(<String>['info', project.path, '--json']);
    expect(code, 64);
    final d =
        (json(out)['diagnostics']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(d['code'], 'design.unsupported');
  });

  test('the suite exit-code table', () {
    final t = McpExitCodes.suite;
    expect(
      <int>[for (final o in McpOutcome.values) t.exitCodeFor(o)],
      <int>[
        0,
        1,
        64,
        65,
        3,
        77,
      ],
    );
  });
}
