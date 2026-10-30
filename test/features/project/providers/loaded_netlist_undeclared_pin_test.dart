// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
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

/// `write_json` from Yosys 0.69 for, without `-check` (the `src` attributes
/// dropped):
///
/// ```verilog
/// (* blackbox *)
/// module INV(input A, output Y, inout VDD, inout VSS);
/// endmodule
/// module top(input a, output y, inout vdd, inout gnd);
///   INV u1(.A(a), .Y(y), .VDD(vdd), .VSS(gnd), .GNDK(gnd));
/// endmodule
/// ```
///
/// Yosys gives the connection to GNDK, a pin INV does not declare, its
/// default direction: `output`.
const String _undeclaredPinJson = '''
{"creator":"Yosys 0.69","modules":{"INV":{"attributes":{"blackbox":"1"},
"ports":{"A":{"direction":"input","bits":[2]},"Y":{"direction":"output",
"bits":[3]},"VDD":{"direction":"inout","bits":[4]},"VSS":{"direction":"inout",
"bits":[5]}},"cells":{},"netnames":{"A":{"hide_name":0,"bits":[2],
"attributes":{}},"VDD":{"hide_name":0,"bits":[4],"attributes":{}},"VSS":{
"hide_name":0,"bits":[5],"attributes":{}},"Y":{"hide_name":0,"bits":[3],
"attributes":{}}}},"top":{"attributes":{"top":"1"},"ports":{"a":{
"direction":"input","bits":[2]},"y":{"direction":"output","bits":[3]},"vdd":{
"direction":"inout","bits":[4]},"gnd":{"direction":"inout","bits":[5]}},
"cells":{"u1":{"hide_name":0,"type":"INV","parameters":{},"attributes":{},
"port_directions":{"A":"input","GNDK":"output","VDD":"inout","VSS":"inout",
"Y":"output"},"connections":{"A":[2],"GNDK":[5],"VDD":[4],"VSS":[5],
"Y":[3]}}},"netnames":{"a":{"hide_name":0,"bits":[2],"attributes":{}},"gnd":{
"hide_name":0,"bits":[5],"attributes":{}},"vdd":{"hide_name":0,"bits":[4],
"attributes":{}},"y":{"hide_name":0,"bits":[3],"attributes":{}}}}}}
''';

class _Runner extends YosysRunner {
  @override
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(String line)? onStderrLine,
    Map<String, String>? environment,
  }) async => const YosysRunSuccess(
    rawJson: _undeclaredPinJson,
    stdout: '',
    stderr: 'yosys says hi',
  );
}

const String _cells = '''
library (cells) {
  cell (INV) {
    pg_pin (VDD) { pg_type : primary_power ; }
    pg_pin (VSS) { pg_type : primary_ground ; }
    pin (A) { direction : input ; }
    pin (Y) { direction : output ; }
  }
}
''';

const String _design = '''
module top(input a, output y, inout vdd, inout gnd);
  INV u1(.A(a), .Y(y), .VDD(vdd), .VSS(gnd), .GNDK(gnd));
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
  late String lib;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('netcrux_undeclared_pin');
    top = p.join(dir.path, 'top.v');
    lib = p.join(dir.path, 'cells.lib');
    File(top).writeAsStringSync(_design);
    File(lib).writeAsStringSync(_cells);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProviderContainer containerWith(YosysRunner runner) => ProviderContainer(
    overrides: [
      ...netcruxTelemetryTestOverrides(),
      yosysRunnerProvider.overrideWith((ref) => runner),
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

  void open(ProviderContainer container) {
    container
        .read(currentProjectProvider.notifier)
        .setProject(
          NetcruxProject.create(
            sourceFiles: <String>[top],
            libertyFiles: <String>[lib],
            blackBoxMissingModules: true,
          ),
        );
  }

  void expectInferred(NetlistModel model, String stderr) {
    final cell = model.modules['top']!.cells['u1']!;
    expect(cell.portDirections, <String, PortDirection>{
      'A': PortDirection.input,
      'GNDK': PortDirection.input,
      'VDD': PortDirection.inout,
      'VSS': PortDirection.inout,
      'Y': PortDirection.output,
    });
    expect(
      stderr,
      startsWith(
        'Warning: 1 connection to 1 pin that the module definition does not '
        'declare, with directions inferred from the wiring: INV.GNDK.',
      ),
    );
  }

  test("a pin the cell library lacks is inferred, through the app's parse "
      'path', () async {
    final container = containerWith(_Runner());
    addTearDown(container.dispose);
    open(container);
    final model = (await container.read(loadedNetlistProvider.future))!;
    expectInferred(model, container.read(elaborationStderrProvider));
  });

  test('with real Yosys, a pin the cell library lacks is inferred', () async {
    if (!_yosysOnPath()) {
      markTestSkipped('yosys is not on PATH on this host');
      return;
    }
    final container = containerWith(YosysRunner());
    addTearDown(container.dispose);
    open(container);
    final model = (await container.read(loadedNetlistProvider.future))!;
    expectInferred(model, container.read(elaborationStderrProvider));
  });
}
