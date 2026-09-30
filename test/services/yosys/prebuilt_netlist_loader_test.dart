// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/web/web_json_loader.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

const String _seedNetlist =
    'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json';

void main() {
  group('PrebuiltNetlistLoader', () {
    test('reads and parses a netlist file on a background isolate', () async {
      final model = await const PrebuiltNetlistLoader().load(
        File(_seedNetlist).absolute.path,
      );
      expect(model, isNotNull);
      expect(model!.topModule?.name, 'top');
      expect(model.modules.keys, containsAll(<String>['top', 'cpu', 'alu']));
    });

    test('parses in place when isolates are unavailable', () async {
      final raw = File(_seedNetlist).readAsStringSync();
      final locations = <String>[];
      final loader = PrebuiltNetlistLoader(
        read: (location) async {
          locations.add(location);
          return raw;
        },
        parseOnIsolate: false,
      );
      final model = await loader.load('blob:https://app.netcrux.app/1');
      expect(locations, <String>['blob:https://app.netcrux.app/1']);
      expect(model?.topModule?.name, 'top');
    });

    test('an unreadable location surfaces WebJsonLoadException', () async {
      await expectLater(
        const PrebuiltNetlistLoader().load('/no/such/netlist.json'),
        throwsA(isA<WebJsonLoadException>()),
      );
    });

    test('a document that is not a netlist surfaces a parse error', () async {
      final loader = PrebuiltNetlistLoader(
        read: (_) async => '{"not": "a netlist"',
        parseOnIsolate: false,
      );
      await expectLater(
        loader.load('bad.json'),
        throwsA(isA<YosysJsonParseException>()),
      );
    });
  });
}
