// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The cases of `spec/mcp/cases.json`, run through either door: the
/// `netcrux <command> ... --json` command line and the `netcrux mcp` tool of
/// the same name.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:netcrux/headless/net_design.dart';
import 'package:netcrux/headless/netcrux_cli.dart';
import 'package:path/path.dart' as p;

import 'fake_elaborator.dart';

/// One case: a tool, its MCP arguments, and its golden document.
class SpecCase {
  SpecCase._(this.golden, this.tool, this.arguments, this.door, this.yosys);

  factory SpecCase._fromJson(Map<String, Object?> json) => SpecCase._(
    json['golden']! as String,
    json['tool']! as String,
    json['arguments']! as Map<String, Object?>,
    json['door'] as String? ?? 'both',
    json['yosys'] as String? ?? 'counter',
  );

  /// The golden's path under `spec/mcp/goldens/`.
  final String golden;

  /// The tool, which is also the command.
  final String tool;

  /// The `tools/call` arguments; paths are relative to the root.
  final Map<String, Object?> arguments;

  /// `both` when the command line can be given the same arguments; `mcp`
  /// when only the server answers (its own argument and confinement checks).
  final String door;

  /// What the stand-in Yosys does for sources: `counter` elaborates them
  /// into `counter.json`, `fails` stops with a syntax error, `missing` is
  /// not installed.
  final String yosys;

  @override
  String toString() => golden;
}

/// `spec/mcp/cases.json`, read from the package root.
class SpecCases {
  SpecCases._(this.root, this.goldenRoot, this.goldenVersion, this.cases);

  /// Loads the cases.
  factory SpecCases.load() {
    final json =
        jsonDecode(File('spec/mcp/cases.json').readAsStringSync())
            as Map<String, Object?>;
    return SpecCases._(
      p.absolute(json['root']! as String),
      json['golden_root']! as String,
      json['golden_version']! as String,
      <SpecCase>[
        for (final c in json['cases']! as List<Object?>)
          SpecCase._fromJson(c! as Map<String, Object?>),
      ],
    );
  }

  /// The server's root, absolute on this machine.
  final String root;

  /// What the root reads as in a golden.
  final String goldenRoot;

  /// The program version a golden names.
  final String goldenVersion;

  /// Every case.
  final List<SpecCase> cases;

  /// [text] with this machine's root, plain and percent-encoded, written as
  /// the goldens write it.
  String normalize(String text) => text
      .replaceAll(mcpPercentEncode(root), mcpPercentEncode(goldenRoot))
      .replaceAll(root, goldenRoot);

  /// The golden document of [c], as written.
  String golden(SpecCase c) =>
      File(p.join('spec', 'mcp', 'goldens', c.golden)).readAsStringSync();

  /// The stand-in Yosys [c] names.
  FakeElaborator elaborator(SpecCase c) => switch (c.yosys) {
    'fails' => FakeElaborator.failing(),
    'missing' => FakeElaborator(
      FakeElaborator.failing().result,
      available: false,
    ),
    _ => FakeElaborator.writing(p.join(root, 'counter.json')),
  };

  /// A command line for [c]: the program the goldens name, and the Yosys
  /// [c] names.
  NetCruxCli cli(SpecCase c, {McpProgram? program}) => NetCruxCli(
    program: program ?? McpProgram(name: 'netcrux', version: goldenVersion),
    reader: NetDesignReader(elaborator: elaborator(c)),
    telemetry: () => null,
  );

  /// What the `netcrux mcp` tool answers for [c]: the decoded tool result.
  Future<Map<String, Object?>> callTool(NetCruxCli cli, SpecCase c) async {
    final server = cli.server(root: root);
    final line = await server.handleLine(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': <String, Object?>{'name': c.tool, 'arguments': c.arguments},
      }),
    );
    final reply = jsonDecode(line!) as Map<String, Object?>;
    return reply['result']! as Map<String, Object?>;
  }

  /// The command line [c]'s arguments become, as the server builds it.
  List<String> argv(NetCruxCli cli, SpecCase c) {
    final tool = cli.commands.firstWhere((x) => x.name == c.tool).tool;
    final checked = tool.check(c.arguments, Confinement(root));
    if (checked is! McpArguments) {
      throw StateError('$c: the arguments are refused; use door "mcp"');
    }
    return <String>[tool.command, ...checked.argv, '--json'];
  }

  /// What `netcrux <argv>` writes on stdout, and its exit code.
  Future<(String, int)> runCommandLine(
    NetCruxCli cli,
    List<String> argv,
  ) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await cli.run(argv, out: out, err: err);
    return (out.toString(), code);
  }
}
