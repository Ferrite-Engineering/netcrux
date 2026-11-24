// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// What the `design` arguments name and how a design is read: the kinds of
// file, the request Yosys gets, the top module, the fingerprint, and the two
// designs a server holds.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/headless/net_design.dart';
import 'package:netcrux/headless/netcrux_cli.dart';
import 'package:path/path.dart' as p;

import 'support/fake_elaborator.dart';

void main() {
  final fixtures = p.absolute('spec', 'fixtures');
  final netlist = p.join(fixtures, 'counter.json');
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('netcrux_design_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, String text) {
    final file = File(p.join(dir.path, name))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    return file.path;
  }

  Future<Map<String, Object?>> doc(
    List<String> argv, {
    FakeElaborator? yosys,
  }) async {
    final out = StringBuffer();
    await NetCruxCli(
      reader: NetDesignReader(elaborator: yosys ?? FakeElaborator.failing()),
      telemetry: () => null,
    ).run(<String>[...argv, '--json'], out: out, err: StringBuffer());
    return jsonDecode(out.toString()) as Map<String, Object?>;
  }

  List<String> codes(Map<String, Object?> d) => <String>[
    for (final x in d['diagnostics']! as List<Object?>)
      (x! as Map<String, Object?>)['code']! as String,
  ];

  group('what a design argument is', () {
    test('by its name', () {
      expect(netDesignFileKind('/a/n.JSON'), NetDesignFileKind.netlist);
      expect(
        netDesignFileKind('/a/d.crux-project'),
        NetDesignFileKind.manifest,
      );
      expect(netDesignFileKind('/a/.crux-project'), NetDesignFileKind.manifest);
      expect(netDesignFileKind('/a/files.f'), NetDesignFileKind.filelist);
      expect(netDesignFileKind('/a/cells.lib'), NetDesignFileKind.liberty);
      expect(
        netDesignFileKind('/a/p.netcrux-project'),
        NetDesignFileKind.netcruxFile,
      );
      expect(netDesignFileKind('/a/s.netcrux'), NetDesignFileKind.netcruxFile);
      expect(netDesignFileKind('/a/top.sv'), NetDesignFileKind.source);
      expect(netDesignFileKind('/a/top.vhd'), NetDesignFileKind.source);
    });

    test('a netlist or a manifest is the whole design', () async {
      final d = await doc(<String>['info', netlist, p.join(fixtures, 'top.v')]);
      expect(d['outcome'], 'usage_error');
      expect(codes(d), <String>['design.mixed']);
    });

    test('a cell library is refused, from a filelist too', () async {
      final lib = write('cells.lib', 'library (x) {}\n');
      final d = await doc(<String>['info', p.join(fixtures, 'top.v'), lib]);
      expect(codes(d), <String>['design.liberty_unsupported']);
      final f = write('d.f', '${p.join(fixtures, 'top.v')}\ncells.lib\n');
      write('cells.lib', 'library (x) {}\n');
      expect(codes(await doc(<String>['info', f])), <String>[
        'design.liberty_unsupported',
      ]);
    });
  });

  group('the request Yosys gets', () {
    test("a filelist's sources, defines and include directories, in "
        'order', () async {
      final f = write(
        'd.f',
        '+define+WIDTH=4 +define+FAST\n+incdir+inc\n'
            '${p.join(fixtures, 'top.v')}\n${p.join(fixtures, 'inc.v')}\n',
      );
      final yosys = FakeElaborator.writing(netlist);
      final d = await doc(<String>['info', f, '--top', 'top'], yosys: yosys);
      expect(d['outcome'], 'completed');
      final request = yosys.requests.single;
      expect(request.sourcePaths, <String>[
        p.join(fixtures, 'top.v'),
        p.join(fixtures, 'inc.v'),
      ]);
      expect(request.defines, <String>['WIDTH=4', 'FAST']);
      expect(request.includePaths, <String>[p.join(dir.path, 'inc')]);
      expect(request.topModule, 'top');
      // The fingerprint covers the defines, sorted by name.
      final text = StringBuffer();
      for (final s in <String>['top.v', 'inc.v']) {
        text.write(
          '${sha256.convert(File(p.join(fixtures, s)).readAsBytesSync())}'
          '  $s\n',
        );
      }
      text.write('top=top\ndefine FAST=\ndefine WIDTH=4\n');
      expect(
        ((d['design']! as Map<String, Object?>)['fingerprint']!
            as Map<String, Object?>)['value'],
        sha256.convert(utf8.encode(text.toString())).toString(),
      );
    });

    test("a manifest's sources and its declared top; its locations carry "
        'no link', () async {
      final m = write(
        'd.crux-project',
        'version: 1\ndesign:\n  top: top\n  sources:\n'
            '    - ${p.join(fixtures, 'top.v')}\n'
            '    - ${p.join(fixtures, 'inc.v')}\n',
      );
      final yosys = FakeElaborator.writing(netlist);
      final d = await doc(<String>['search', m, 'u_inc'], yosys: yosys);
      expect(yosys.requests.single.topModule, 'top');
      final hit =
          ((d['body']! as Map<String, Object?>)['hits']! as List<Object?>)
                  .first!
              as Map<String, Object?>;
      final location = hit['location']! as Map<String, Object?>;
      expect(location['file'], m);
      expect(location['link'], isNull);
    });

    test('a single source is cited, and linked', () async {
      final source = write(
        'top.v',
        File(p.join(fixtures, 'top.v')).readAsStringSync(),
      );
      final d = await doc(<String>[
        'connections',
        source,
        'top.u_inc',
      ], yosys: FakeElaborator.writing(netlist));
      final location =
          (d['body']! as Map<String, Object?>)['location']!
              as Map<String, Object?>;
      expect(location['file'], source);
      expect(
        location['link'],
        netCruxLink(source, kind: McpElementKind.cell, name: 'top.u_inc'),
      );
    });
  });

  group('the top module', () {
    String untopped() => write(
      'n.json',
      File(netlist).readAsStringSync().replaceFirst(
        '"top": "00000000000000000000000000000001",',
        '',
      ),
    );

    test('a netlist that marks none needs --top', () async {
      final d = await doc(<String>['info', untopped()]);
      expect(d['outcome'], 'input_error');
      expect(codes(d), <String>['design.no_top']);
    });

    test('given one, it is read rooted there, and carries no link', () async {
      final d = await doc(<String>[
        'connections',
        untopped(),
        'n',
        '--top',
        'top',
      ]);
      expect(d['outcome'], 'completed');
      expect(codes(d), <String>['link.unavailable']);
      final body = d['body']! as Map<String, Object?>;
      expect(body['path'], 'top.n');
      expect((body['location']! as Map<String, Object?>)['link'], isNull);
    });

    test('one the netlist does not have, or another than it marks', () async {
      expect(
        codes(await doc(<String>['info', netlist, '--top', 'nope'])),
        <String>[
          'design.top_not_found',
        ],
      );
      expect(
        codes(await doc(<String>['info', netlist, '--top', 'inc'])),
        <String>[
          'design.top_mismatch',
        ],
      );
    });
  });

  group('the designs a server holds', () {
    test('a design read once is not elaborated again', () async {
      final yosys = FakeElaborator.writing(netlist);
      final cli = NetCruxCli(
        reader: NetDesignReader(elaborator: yosys),
        telemetry: () => null,
      );
      final design = <String>[p.join(fixtures, 'design.f')];
      await cli.document('info', <String>[...design, '--json']);
      await cli.document('search', <String>[...design, 'a', '--json']);
      expect(yosys.requests, hasLength(1));
    });

    test('two are held; the third evicts the oldest', () async {
      final reader = NetDesignReader(
        elaborator: FakeElaborator.writing(netlist),
      );
      final a = write('a.json', File(netlist).readAsStringSync());
      final b = write('b.json', '${File(netlist).readAsStringSync()} ');
      final c = write('c.json', '${File(netlist).readAsStringSync()}  ');
      for (final f in <String>[a, b, c]) {
        await reader.read(await resolveNetDesign(<String>[f]));
      }
      expect(reader.heldKeys, hasLength(2));
      final first = netDesignFingerprint(
        await resolveNetDesign(<String>[a]),
      )!.value;
      expect(reader.heldKeys, isNot(contains(first)));
    });

    test('a file that changes is read again', () async {
      final yosys = FakeElaborator.writing(netlist);
      final reader = NetDesignReader(elaborator: yosys);
      final source = write('top.v', 'module top; endmodule\n');
      await reader.read(await resolveNetDesign(<String>[source]));
      File(source).writeAsStringSync('module top; wire w; endmodule\n');
      await reader.read(await resolveNetDesign(<String>[source]));
      expect(yosys.requests, hasLength(2));
    });
  });

  group('the files a filelist or manifest names, checked first', () {
    test('each filelist is judged before it is opened', () async {
      final asked = <String>[];
      final refusal = await checkNetDesignNamedFiles(
        <String>[p.join(fixtures, 'escape_nested.f')],
        (path) {
          asked.add(path);
          return path.endsWith('outside.f') ? 'refused $path' : null;
        },
      );
      expect(refusal, 'refused ${p.join(p.dirname(fixtures), 'outside.f')}');
      expect(asked.first, p.join(fixtures, 'escape_nested.f'));
    });

    test('every source, include directory and netlist is judged', () async {
      final asked = <String>[];
      final f = write('d.f', '+incdir+inc\na.v\n');
      final m = write(
        'd.crux-project',
        'version: 1\ndesign:\n  sources:\n    - b.v\nartifacts:\n'
            '  netlist: n.json\n',
      );
      expect(
        await checkNetDesignNamedFiles(<String>[f, m], (path) {
          asked.add(path);
          return null;
        }),
        isNull,
      );
      // The manifest parser resolves its directory's links (/private/var on
      // macOS), so the names are compared.
      expect(
        asked.map(p.basename),
        containsAll(<String>['inc', 'a.v', 'b.v', 'n.json']),
      );
    });
  });
}
