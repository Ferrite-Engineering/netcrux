// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The headless `netcrux` command line and its MCP server.
///
/// `netcrux info|search|connections ... --json` writes one document
/// (`crux_mcp`'s envelope) and exits with the suite's code for its outcome;
/// `netcrux mcp` serves the same three commands as tools over stdio, each
/// call running the command's own code, so a tool's text is byte for byte
/// what the command writes. No Flutter anywhere below this file:
/// `test/static/headless_cli_closure_test.dart` walks the imports.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crux_mcp/crux_mcp.dart';
import 'package:netcrux/headless/cli_version.dart';
import 'package:netcrux/headless/net_commands.dart';
import 'package:netcrux/headless/net_design.dart';

/// The `instructions` paragraph `initialize` returns: when to call the
/// server, and to cite with links. The full text is `docs/agent/NETCRUX.md`.
const String kNetCruxMcpInstructions =
    'NetCrux reads a hardware design as Yosys elaborates it: Verilog, '
    'SystemVerilog or VHDL sources, a Yosys JSON netlist, or a .crux-project. '
    'Call info first for the top module and hierarchy, search to find the '
    'full name of a cell, net, port or module, and connections for what '
    'drives a net or what a cell is wired to. Names are hierarchical, '
    'dot-separated, rooted at the top module. Cite each finding with the '
    'link in its location, which opens the cell or net in NetCrux for a '
    'person to check, or with its source line.';

/// The `--license-file` help of the open-core binary: its tools need no
/// licence.
const String kNetCruxOpenCoreLicenseHelp =
    'A licence file for the tools that need one. The three tools of this '
    'binary are free and read none.';

/// The headless command line: `netcrux <command> ...`.
class NetCruxCli {
  /// A command line serving [commands], reading designs through [reader].
  ///
  /// [telemetry] makes the `mcp` server's counter, once the server's
  /// arguments are read (so it may ask for [NetCommandContext.licenseFile]);
  /// by default the one that sends under the consent the desktop app
  /// recorded (never when `CI` is set). [instructions] is the paragraph
  /// `initialize` returns and [licenseHelp] the `mcp --license-file` help:
  /// another edition serving more commands gives its own. [mapProblem]
  /// exists for the mutation proof only.
  NetCruxCli({
    List<NetCommand>? commands,
    NetDesignReader? reader,
    this.program = kNetCruxProgram,
    this.instructions = kNetCruxMcpInstructions,
    this.licenseHelp = kNetCruxOpenCoreLicenseHelp,
    McpExitCodes? exitCodes,
    FutureOr<McpTelemetry?> Function()? telemetry,
    NetDesignProblemMap mapProblem = classifyNetDesignProblem,
  }) : commands = List<NetCommand>.unmodifiable(
         commands ?? openCoreNetCommands(),
       ),
       exitCodes = exitCodes ?? McpExitCodes.suite,
       _telemetry = telemetry ?? netCruxMcpTelemetry,
       commandContext = NetCommandContext(
         reader: reader ?? NetDesignReader(),
         program: program,
         mapProblem: mapProblem,
       );

  /// The subcommands, which are also the server's tools, in listing order.
  final List<NetCommand> commands;

  /// The program the documents name.
  final McpProgram program;

  /// The `instructions` paragraph the server's `initialize` returns.
  final String instructions;

  /// The help of `mcp --license-file`.
  final String licenseHelp;

  /// The exit code of each outcome.
  final McpExitCodes exitCodes;

  /// Where designs are read.
  final NetCommandContext commandContext;

  final FutureOr<McpTelemetry?> Function() _telemetry;

  NetCommand? _command(String name) {
    for (final c in commands) {
      if (c.name == name) return c;
    }
    return null;
  }

  ArgParser _parserFor(NetCommand command) {
    final parser = ArgParser()
      ..addFlag('json', negatable: false, help: 'Write the JSON document.')
      ..addFlag('help', abbr: 'h', negatable: false, help: 'This text.');
    command.addFlags(parser);
    return parser;
  }

  /// The document [command] writes for [args] (everything after the command
  /// name). The `--json` door and every tool call come through here.
  Future<McpDocument> document(String command, List<String> args) async {
    final c = _command(command);
    if (c == null) {
      return McpDocument.usage(
        tool: program,
        command: null,
        message: 'unknown command `$command`',
      );
    }
    try {
      final parsed = _parserFor(c).parse(args);
      return await c.run(commandContext, parsed);
    } on FormatException catch (e) {
      return McpDocument.usage(
        tool: program,
        command: c.name,
        message: e.message,
      );
    } on NetUsageException catch (e) {
      return McpDocument.usage(
        tool: program,
        command: c.name,
        message: e.message,
      );
    }
  }

  /// Runs [argv] as the binary would: writes to [out] and [err], serves
  /// `mcp` on [input] and [output], and returns the exit code.
  Future<int> run(
    List<String> argv, {
    required StringSink out,
    required StringSink err,
    Stream<List<int>>? input,
    StreamSink<List<int>>? output,
  }) async {
    if (argv.isEmpty || argv.first == '--help' || argv.first == '-h') {
      (argv.isEmpty ? err : out).write(usage());
      return argv.isEmpty ? exitCodes.usageError : 0;
    }
    if (argv.first == '--version') {
      out.writeln('${program.name} ${program.version}');
      return 0;
    }
    final name = argv.first;
    final rest = argv.sublist(1);
    if (name == 'mcp') {
      return await _serve(
        rest,
        out: out,
        err: err,
        input: input,
        output: output,
      );
    }
    final command = _command(name);
    if (command == null) {
      err
        ..writeln('${program.name}: unknown command `$name`')
        ..write(usage());
      return exitCodes.usageError;
    }
    if (rest.contains('--help') || rest.contains('-h')) {
      out
        ..writeln(command.summary)
        ..writeln()
        ..writeln('Usage: ${command.invocation}')
        ..writeln(_parserFor(command).usage);
      return 0;
    }
    final doc = await document(name, rest);
    if (rest.contains('--json')) {
      out.write(doc.render());
    } else {
      final body = doc.body;
      if (body != null) {
        command.describe(body).forEach(out.writeln);
      }
      for (final d in doc.diagnostics) {
        err.writeln('${d.severity.name}: ${d.message}');
        if (d.fix != null) err.writeln('  fix: ${d.fix}');
      }
      if (doc.outcome == McpOutcome.usageError) {
        err.writeln('Usage: ${command.invocation}');
      }
    }
    return exitCodes.exitCodeFor(doc.outcome);
  }

  /// The top-level help.
  String usage() {
    final b = StringBuffer()
      ..writeln(
        '${program.name} ${program.version}: read an elaborated design from '
        'the command line, or serve it to an agent over MCP.',
      )
      ..writeln()
      ..writeln('Commands:');
    for (final c in commands) {
      b.writeln('  ${c.name.padRight(12)} ${c.summary}');
    }
    b
      ..writeln(
        '  ${'mcp'.padRight(12)} Serve these commands as MCP tools on stdio.',
      )
      ..writeln()
      ..writeln(
        'A design is HDL sources (Verilog, SystemVerilog, VHDL) and .f '
        'filelists, elaborated by Yosys on PATH; one Yosys JSON netlist; or '
        'one .crux-project.',
      )
      ..writeln(
        'Add --json for the JSON document; `${program.name} <command> '
        "--help` for a command's flags.",
      );
    return b.toString();
  }

  /// The MCP server over these commands, its paths held inside [root].
  McpServer server({required String root, McpTelemetry? telemetry}) =>
      McpServer(
        program: program,
        instructions: instructions,
        tools: <McpTool>[for (final c in commands) c.tool],
        confinement: Confinement(root),
        telemetry: telemetry,
        runner: (call) async => McpCommandOutput.document(
          await document(call.tool.command, <String>[
            ...call.arguments.argv,
            '--json',
          ]),
        ),
      );

  Future<int> _serve(
    List<String> args, {
    required StringSink out,
    required StringSink err,
    Stream<List<int>>? input,
    StreamSink<List<int>>? output,
  }) async {
    final parser = ArgParser()
      ..addOption(
        'root',
        help: 'Every path a tool receives must be inside it.',
        valueHelp: 'dir',
        defaultsTo: Directory.current.path,
      )
      ..addOption('license-file', help: licenseHelp, valueHelp: 'path')
      ..addFlag('help', abbr: 'h', negatable: false, help: 'This text.');
    final ArgResults parsed;
    try {
      parsed = parser.parse(args);
    } on FormatException catch (e) {
      err
        ..writeln('${program.name} mcp: ${e.message}')
        ..writeln(parser.usage);
      return exitCodes.usageError;
    }
    if (parsed.flag('help')) {
      out
        ..writeln(
          'Serve ${commands.map((c) => c.name).join(', ')} as MCP tools: '
          'newline-delimited JSON-RPC on stdin and stdout.',
        )
        ..writeln()
        ..writeln(
          'Usage: ${program.name} mcp [--root <dir>] '
          '[--license-file <path>]',
        )
        ..writeln(parser.usage);
      return 0;
    }
    if (parsed.rest.isNotEmpty) {
      err.writeln('${program.name} mcp: unexpected `${parsed.rest.first}`');
      return exitCodes.usageError;
    }
    final root = parsed.option('root')!;
    commandContext.licenseFile = parsed.option('license-file');
    final server = this.server(root: root, telemetry: await _telemetry());
    final problem = server.confinement.rootProblem();
    if (problem != null) {
      err.writeln('${program.name} mcp: $problem');
      return exitCodes.usageError;
    }
    await server.serve(input ?? stdin, output ?? stdout);
    return 0;
  }
}

/// The `mcp.tool_call` counter of the open-core binary: sent only under the
/// consent the NetCrux desktop app recorded on this machine, and never when
/// the `CI` environment variable is set.
McpTelemetry netCruxMcpTelemetry() =>
    McpTelemetry.desktop(netCruxHeadlessTelemetry());

/// The headless sender behind [netCruxMcpTelemetry].
HeadlessTelemetry netCruxHeadlessTelemetry() => HeadlessTelemetry(
  product: CruxTelemetryProduct.netcrux,
  pro: false,
  appVersion: kNetCruxCliVersion,
);
