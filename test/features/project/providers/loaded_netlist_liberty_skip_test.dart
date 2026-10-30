// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/services/liberty/liberty_stub_service.dart';
import 'package:netcrux/services/liberty/liberty_stub_service_provider.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_runner_provider.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/telemetry_test_overrides.dart';

// A Liberty file NetCrux cannot read is skipped with a warning, through a
// real Yosys. Skips when Yosys is not on PATH.

const String _design = '''
module top(input a, output y, inout vdd, inout gnd);
  INV u1(.A(a), .Y(y), .VDD(vdd), .VSS(gnd));
endmodule
''';

bool _yosysOnPath() {
  try {
    return Process.runSync('yosys', <String>['-V']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  late Directory dir;
  late String top;
  late String bad;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('netcrux_liberty_skip');
    top = p.join(dir.path, 'top.v');
    bad = p.join(dir.path, 'bad.lib');
    File(top).writeAsStringSync(_design);
    File(bad).writeAsStringSync('library (x) {\n  cell (INV) {\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProviderContainer open({required bool blackBoxes}) {
    final container = ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        yosysRunnerProvider.overrideWith((ref) => YosysRunner()),
        yosysAvailabilityProvider.overrideWith(
          (ref) async => const YosysAvailability.available(
            executablePath: 'yosys',
            versionString: 'Yosys test',
          ),
        ),
        libertyStubServiceProvider.overrideWith(
          (ref) => LibertyStubService(cacheBaseDirectory: () async => dir),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(currentProjectProvider.notifier)
        .setProject(
          NetcruxProject.create(
            sourceFiles: <String>[top],
            libertyFiles: <String>[bad],
            blackBoxMissingModules: blackBoxes,
          ),
        );
    return container;
  }

  test('an unreadable library is skipped with a warning, and its cells are '
      'black boxes', () async {
    if (!_yosysOnPath()) {
      markTestSkipped('yosys is not on PATH on this host');
      return;
    }
    final container = open(blackBoxes: true);
    final model = (await container.read(loadedNetlistProvider.future))!;
    final stderr = container.read(elaborationStderrProvider);
    expect(stderr, contains('Warning: Cell library skipped'));
    expect(stderr, contains(bad));
    expect(stderr, contains('Warning: No definition found for 1 module type'));
    expect(model.modules.containsKey('INV'), isFalse);
    expect(
      model.modules['top']!.cells['u1']!.portDirections.keys,
      containsAll(<String>['A', 'Y', 'VDD', 'VSS']),
    );
  });

  test('with black boxes off, the cells of an unreadable library are the usual '
      'missing-module error', () async {
    if (!_yosysOnPath()) {
      markTestSkipped('yosys is not on PATH on this host');
      return;
    }
    final container = open(blackBoxes: false);
    await expectLater(
      container.read(loadedNetlistProvider.future),
      throwsA(
        isA<LoadedNetlistException>()
            .having((e) => e.kind, 'kind', LoadedNetlistErrorKind.missingModule)
            .having((e) => e.missingModule, 'missingModule', 'INV'),
      ),
    );
    expect(container.read(elaborationStderrProvider), contains(bad));
  });

  test('a missing library is skipped the same way', () async {
    if (!_yosysOnPath()) {
      markTestSkipped('yosys is not on PATH on this host');
      return;
    }
    File(bad).deleteSync();
    final container = open(blackBoxes: true);
    final model = (await container.read(loadedNetlistProvider.future))!;
    final stderr = container.read(elaborationStderrProvider);
    expect(stderr, contains('Warning: Cell library skipped'));
    expect(stderr, contains('file not found'));
    expect(model.modules['top']!.cells, contains('u1'));
  });
}
