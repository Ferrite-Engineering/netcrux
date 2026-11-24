// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `spec/mcp/`: every tool's golden documents, one per outcome it can produce,
// against both doors.
//
// - The `netcrux mcp` tool's `content[0]` text, with this machine's root
//   written as the goldens write it, is the golden byte for byte. The
//   goldens were written by hand from `spec/fixtures/counter.json` (every
//   count, name, width, pin, `src` line and link derived from the netlist's
//   own members, the fingerprints from `shasum -a 256` of the files and of
//   the scheme's text), not copied from output. Sources are elaborated by a
//   stand-in Yosys (`support/fake_elaborator.dart`) that answers with that
//   netlist, fails with a syntax error, or is not installed.
// - The same text is byte for byte what `netcrux <command> ... --json`
//   writes for the same arguments, and the command exits with the suite's
//   code for the outcome: the two doors cannot disagree.
// - Every golden keeps `spec/mcp/schemas/`: the envelope and its body.
// - Every link in every golden parses with the app's own link reader, names
//   the file and the element of the location that carries it, and is found
//   in the netlist by the rule the app opens it with.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/links/netcrux_link.dart';
import 'package:netcrux/services/links/netcrux_link_placement.dart';
import 'package:netcrux/services/yosys/isolate_netlist_parser.dart';
import 'package:path/path.dart' as p;

import 'support/json_schema_check.dart';
import 'support/spec_cases.dart';

Map<String, Object?> _schema(String name) =>
    jsonDecode(File(p.join('spec', 'mcp', 'schemas', name)).readAsStringSync())
        as Map<String, Object?>;

/// Every object under [json] that has a `link` member, with its JSON path.
Iterable<(String, Map<String, Object?>)> _linked(
  Object? json,
  String at,
) sync* {
  if (json is Map<String, Object?>) {
    if (json.containsKey('link')) yield (at, json);
    for (final e in json.entries) {
      yield* _linked(e.value, '$at.${e.key}');
    }
  } else if (json is List<Object?>) {
    for (var i = 0; i < json.length; i++) {
      yield* _linked(json[i], '$at[$i]');
    }
  }
}

void main() {
  final spec = SpecCases.load();
  final documentSchema = _schema('document.schema.json');

  group('each golden is what the tool answers', () {
    for (final c in spec.cases) {
      test(c.golden, () async {
        final result = await spec.callTool(spec.cli(c), c);
        final content = result['content']! as List<Object?>;
        expect(content, hasLength(1));
        final item = content.single! as Map<String, Object?>;
        expect(item['type'], 'text');
        final text = item['text']! as String;
        expect(spec.normalize(text), spec.golden(c));
        final outcome = McpOutcome.fromWireName(
          (jsonDecode(text) as Map<String, Object?>)['outcome']! as String,
        );
        expect(result['isError'], outcome!.isError);
      });
    }
  });

  group('the tool and the command line write the same bytes', () {
    for (final c in spec.cases.where((c) => c.door == 'both')) {
      test(c.golden, () async {
        // One program for both doors, the real one, so nothing is normalized.
        const program = McpProgram(name: 'netcrux', version: '9.9.9');
        final cli = spec.cli(c, program: program);
        final result = await spec.callTool(cli, c);
        final toolText =
            ((result['content']! as List<Object?>).single!
                    as Map<String, Object?>)['text']!
                as String;
        final (stdoutText, code) = await spec.runCommandLine(
          spec.cli(c, program: program),
          spec.argv(cli, c),
        );
        expect(stdoutText, toolText);
        final outcome = McpOutcome.fromWireName(
          (jsonDecode(stdoutText) as Map<String, Object?>)['outcome']!
              as String,
        )!;
        expect(code, McpExitCodes.suite.exitCodeFor(outcome));
      });
    }
  });

  group('each golden keeps the schemas', () {
    for (final c in spec.cases) {
      test(c.golden, () {
        final doc = jsonDecode(spec.golden(c)) as Map<String, Object?>;
        expect(jsonSchemaProblems(doc, documentSchema), isEmpty);
        final body = doc['body'];
        if (body != null) {
          expect(
            jsonSchemaProblems(body, _schema('${c.tool}.body.schema.json')),
            isEmpty,
          );
        }
        final errors = (doc['diagnostics']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .where((d) => d['severity'] == 'error');
        if (doc['outcome'] == 'completed') {
          expect(body, isNotNull);
          expect(errors, isEmpty);
        } else {
          expect(body, isNull);
          expect(errors, isNotEmpty);
        }
      });
    }
  });

  test('the schema checker rejects what the schemas forbid', () {
    final good = jsonDecode(spec.golden(spec.cases.first));
    expect(jsonSchemaProblems(good, documentSchema), isEmpty);
    final extra = <String, Object?>{
      ...good as Map<String, Object?>,
      'extra': 1,
    };
    expect(jsonSchemaProblems(extra, documentSchema), isNotEmpty);
    final missing = Map<String, Object?>.of(good)..remove('engines');
    expect(jsonSchemaProblems(missing, documentSchema), isNotEmpty);
    final badOutcome = Map<String, Object?>.of(good)..['outcome'] = 'fine';
    expect(jsonSchemaProblems(badOutcome, documentSchema), isNotEmpty);
    final body = Map<String, Object?>.of(good['body']! as Map<String, Object?>)
      ..remove('truncated');
    expect(
      jsonSchemaProblems(body, _schema('info.body.schema.json')),
      isNotEmpty,
    );
  });

  group('every link in every golden opens what its location names', () {
    late final model = parseNetlistFileOnIsolate(
      p.join(spec.root, 'counter.json'),
    );

    for (final c in spec.cases) {
      test(c.golden, () async {
        final netlist = (await model)!;
        final doc = jsonDecode(spec.golden(c));
        for (final (at, location) in _linked(doc, r'$')) {
          final link = location['link'] as String?;
          if (link == null) continue;
          final parsed = parseNetCruxLink(link);
          expect(parsed, isA<NetCruxLinkParsed>(), reason: at);
          final read = (parsed as NetCruxLinkParsed).link;
          expect(read.file, location['file'], reason: at);
          final kind = location.containsKey('cell')
              ? NetCruxLinkElementKind.cell
              : NetCruxLinkElementKind.net;
          expect(read.kind, kind, reason: at);
          expect(read.name, location[kind.name], reason: at);
          // The app places it, by the rule it opens links with.
          expect(
            findNetCruxLinkElement(netlist, kind, read.name!),
            isNotNull,
            reason: at,
          );
          // crux_mcp reads it back as the location it was built from.
          expect(McpLocation.fromJson(location), isA<McpElementLocation>());
        }
      });
    }

    test('a design of sources that do not elaborate alone carries no link, '
        'and one that does is the only source design that links', () {
      var multiSource = 0;
      for (final c in spec.cases) {
        final design = (c.arguments['design']! as List<Object?>).cast<String>();
        final sources = design.where(
          (f) => const <String>['.v', '.sv', '.vhd'].any(f.endsWith),
        );
        final alone = design.length == 1 && sources.length == 1;
        if (sources.isEmpty || alone) continue;
        multiSource++;
        for (final (at, l) in _linked(jsonDecode(spec.golden(c)), r'$')) {
          expect(l['link'], isNull, reason: '${c.golden} $at');
        }
      }
      expect(multiSource, greaterThanOrEqualTo(3));
    });

    test('the goldens carry links, and locations without one', () async {
      final links = <String?>[
        for (final c in spec.cases)
          for (final (_, l) in _linked(jsonDecode(spec.golden(c)), r'$'))
            l['link'] as String?,
      ];
      expect(links.whereType<String>().length, greaterThanOrEqualTo(10));
      expect(links.where((l) => l == null), isNotEmpty);
    });

    test('a location without a link names nothing the app can place, or a '
        'file a link may not open', () async {
      final netlist = (await model)!;
      for (final c in spec.cases) {
        for (final (at, l) in _linked(jsonDecode(spec.golden(c)), r'$')) {
          if (l['link'] != null) continue;
          final kind = l.containsKey('cell')
              ? NetCruxLinkElementKind.cell
              : NetCruxLinkElementKind.net;
          final file = l['file']! as String;
          final placeable =
              findNetCruxLinkElement(
                netlist,
                kind,
                l[kind.name]! as String,
              ) !=
              null;
          expect(
            !placeable || !file.endsWith('.json'),
            isTrue,
            reason: '${c.golden} $at',
          );
        }
      }
    });
  });

  test('every tool has a golden for each outcome it can produce', () {
    final byTool = <String, Set<String>>{};
    for (final c in spec.cases) {
      final doc = jsonDecode(spec.golden(c)) as Map<String, Object?>;
      byTool
          .putIfAbsent(c.tool, () => <String>{})
          .add(doc['outcome']! as String);
    }
    // The three free tools read; none has a gate or a licence to refuse, so
    // these four are every outcome they can produce.
    const produced = <String>{
      'completed',
      'usage_error',
      'input_error',
      'engine_error',
    };
    expect(byTool.keys.toSet(), <String>{'info', 'search', 'connections'});
    for (final entry in byTool.entries) {
      expect(entry.value, produced, reason: entry.key);
    }
  });
}
