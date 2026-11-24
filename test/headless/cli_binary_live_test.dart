// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The compiled binary, spoken to over stdio: `<binary> mcp` answers a
// scripted `initialize` and `tools/list`, and one `tools/call` that reads the
// fixture netlist.
//
// `CRUX_MCP_SERVER_BIN` names the binary `tool/build_cli.sh` built
// (`<out>/bundle/bin/netcrux`); the same variable points `crux_mcp`'s
// conformance transcripts at it. Unset, which is every CI run of this suite,
// no test is declared rather than a skipped one: CI holds a ceiling on skips.

@TestOn('vm')
@Tags(<String>['reference-live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/headless/cli_version.dart';
import 'package:netcrux/headless/netcrux_cli.dart';
import 'package:path/path.dart' as p;

void main() {
  final binary = Platform.environment['CRUX_MCP_SERVER_BIN'];
  if (binary == null || binary.isEmpty) return;

  test('the built binary serves the three tools over stdio', () async {
    final client = await McpScriptedClient.start(binary, <String>[
      'mcp',
      '--root',
      p.absolute('spec', 'fixtures'),
    ]);
    final init = await client.request('initialize', <String, Object?>{
      'protocolVersion': '2025-03-26',
      'capabilities': <String, Object?>{},
      'clientInfo': <String, Object?>{'name': 'live-test', 'version': '0'},
    });
    final result = init['result']! as Map<String, Object?>;
    expect(result['protocolVersion'], '2025-03-26');
    expect(result['serverInfo'], <String, Object?>{
      'name': 'netcrux',
      'version': kNetCruxCliVersion,
    });
    expect(result['instructions'], kNetCruxMcpInstructions);

    final list = await client.request('tools/list');
    final tools =
        (list['result']! as Map<String, Object?>)['tools']! as List<Object?>;
    expect(tools.map((t) => (t! as Map<String, Object?>)['name']), <String>[
      'info',
      'search',
      'connections',
    ]);

    final call = await client.request('tools/call', <String, Object?>{
      'name': 'connections',
      'arguments': <String, Object?>{
        'design': <String>['counter.json'],
        'name': 'top.n',
      },
    });
    final content =
        ((call['result']! as Map<String, Object?>)['content']! as List<Object?>)
                .single!
            as Map<String, Object?>;
    final doc = jsonDecode(content['text']! as String) as Map<String, Object?>;
    expect(doc['outcome'], 'completed');
    expect((doc['body']! as Map<String, Object?>)['kind'], 'net');

    final code = await client.close();
    expect(code, 0, reason: client.stderrLines.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
