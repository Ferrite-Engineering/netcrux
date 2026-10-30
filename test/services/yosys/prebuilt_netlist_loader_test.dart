// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/web/web_json_loader.dart';
import 'package:netcrux/services/yosys/black_box_port_inference.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// What a user's own Yosys script writes (`read_liberty -lib`, `read_verilog`,
/// `hierarchy -top top` without `-check`, `proc`, `write_json`; the script,
/// the library and the design sit beside it): the library's cell INV loses its
/// power and ground pins, which the design still connects, and Yosys calls
/// both outputs. MACRO has no module at all.
const String _supplyPinsNetlist = 'test/fixtures/prebuilt/supply_pins/top.json';

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

  group('PrebuiltNetlistLoader pin directions', () {
    void expectInferred(NetlistModel model, BlackBoxReport report) {
      final cells = model.modules['top']!.cells;
      for (final name in <String>['u1', 'u2']) {
        expect(cells[name]!.portDirections, <String, PortDirection>{
          'A': PortDirection.input,
          'GNDK': PortDirection.input,
          'VCCK': PortDirection.input,
          'Y': PortDirection.output,
        }, reason: name);
      }
      // A cell whose type nothing defines is inferred too.
      expect(cells['m1']!.portDirections, <String, PortDirection>{
        'CLK': PortDirection.input,
        'D': PortDirection.input,
        'Q': PortDirection.input,
      });
      expect(report.types, <String>['MACRO']);
      expect(report.undeclaredPins, <String>['INV.GNDK', 'INV.VCCK']);
      expect(report.undeclaredPinCount, 4);
      expect(report.warningLines, hasLength(3));
      expect(
        report.warningLines.first,
        startsWith('Warning: No definition found for 1 module type, '),
      );
      expect(
        report.warningLines[1],
        'Warning: 4 connections to 2 pins that the module definition does '
        'not declare, with directions inferred from the wiring: '
        'INV.GNDK, INV.VCCK.',
      );
    }

    test(
      'a pin the module does not declare is inferred, on an isolate',
      () async {
        final loaded = await const PrebuiltNetlistLoader().loadWithReport(
          File(_supplyPinsNetlist).absolute.path,
        );
        expectInferred(loaded!.model, loaded.report);
      },
    );

    test('a pin the module does not declare is inferred, in place', () async {
      final raw = File(_supplyPinsNetlist).readAsStringSync();
      final loader = PrebuiltNetlistLoader(
        read: (_) async => raw,
        parseOnIsolate: false,
      );
      final loaded = await loader.loadWithReport('blob:supply-pins');
      expectInferred(loaded!.model, loaded.report);
    });

    test('load and parse return the model with the pins inferred', () async {
      final loader = PrebuiltNetlistLoader(
        read: (_) async => File(_supplyPinsNetlist).readAsStringSync(),
        parseOnIsolate: false,
      );
      for (final model in <NetlistModel?>[
        await loader.load('x.json'),
        await loader.parse(File(_supplyPinsNetlist).readAsStringSync()),
      ]) {
        expect(
          model!.modules['top']!.cells['u1']!.portDirections['VCCK'],
          PortDirection.input,
        );
      }
    });

    test('a netlist with nothing to infer reports nothing', () async {
      final loaded = await const PrebuiltNetlistLoader().loadWithReport(
        File(_seedNetlist).absolute.path,
      );
      expect(loaded!.report, BlackBoxReport.none);
    });
  });
}
