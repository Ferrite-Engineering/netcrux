// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/telemetry_test_overrides.dart';

const String _fixtures = 'test/fixtures/prebuilt/supply_pins';

bool _yosysOnPath() {
  try {
    return Process.runSync('yosys', <String>['-V']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// A user runs Yosys from their own script and opens the JSON it wrote
/// (File, Open Netlist JSON, or `netcrux design.json`). The script reads the
/// cell library with `read_liberty -lib`, which drops the library's `pg_pin`s,
/// so the supply connections of each cell are to pins its module does not
/// declare, and `hierarchy` without `-check` writes them as `output`.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('netcrux_user_json'));
  tearDown(() => dir.deleteSync(recursive: true));

  ProviderContainer open(String netlistPath) {
    final container = ProviderContainer(
      overrides: [...netcruxTelemetryTestOverrides()],
    );
    addTearDown(container.dispose);
    container
        .read(currentProjectProvider.notifier)
        .setProject(NetcruxProject.create(sourceFiles: <String>[netlistPath]));
    return container;
  }

  void expectSupplyPinsAreInputs(NetlistModel model, String diagnostics) {
    final cells = model.modules['top']!.cells;
    for (final name in <String>['u1', 'u2']) {
      final directions = cells[name]!.portDirections;
      expect(directions['VCCK'], PortDirection.input, reason: name);
      expect(directions['GNDK'], PortDirection.input, reason: name);
      expect(directions['Y'], PortDirection.output, reason: name);
    }
    expect(
      diagnostics,
      contains(
        'Warning: 4 connections to 2 pins that the module definition does '
        'not declare, with directions inferred from the wiring: '
        'INV.GNDK, INV.VCCK.',
      ),
    );
  }

  test(
    'the checked-in Yosys JSON opens with its supply pins as inputs',
    () async {
      final container = open(File('$_fixtures/top.json').absolute.path);
      final model = (await container.read(loadedNetlistProvider.future))!;
      expectSupplyPinsAreInputs(
        model,
        container.read(elaborationStderrProvider),
      );
    },
  );

  test(
    'opening a netlist with nothing to infer leaves Diagnostics empty',
    () async {
      final container = open(
        File(
          'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
        ).absolute.path,
      );
      await container.read(loadedNetlistProvider.future);
      expect(container.read(elaborationStderrProvider), isEmpty);
    },
  );

  test('a JSON from real Yosys, written by a user script, opens with its '
      'supply pins as inputs', () async {
    if (!_yosysOnPath()) {
      markTestSkipped('yosys is not on PATH on this host');
      return;
    }
    for (final name in <String>['cells.lib', 'top.v', 'run.ys']) {
      File('$_fixtures/$name').copySync(p.join(dir.path, name));
    }
    final result = Process.runSync('yosys', <String>[
      '-q',
      '-s',
      'run.ys',
    ], workingDirectory: dir.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final json = p.join(dir.path, 'out.json');
    // The script's output is what the checked-in fixture holds: in the real
    // run every supply connection is written as an output.
    expect(File(json).readAsStringSync(), contains('"GNDK": "output"'));
    final container = open(json);
    final model = (await container.read(loadedNetlistProvider.future))!;
    expectSupplyPinsAreInputs(
      model,
      container.read(elaborationStderrProvider),
    );
  });
}
