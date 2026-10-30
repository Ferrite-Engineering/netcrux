// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netlist_reader_choice.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/services/yosys/netlist_reader_provider.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_runner_provider.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/run_backed_keeping_json.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// What Yosys 0.69 says of `hierarchy -check` on the design below.
const String _missingStderr =
    r"ERROR: Module `\INV' referenced in module `\top' in cell `\u1' is not "
    'part of the design.\n';

/// `write_json` from Yosys 0.69 for, without `-check` (attributes other
/// than `top` dropped):
///
/// ```verilog
/// module top(input a, input clk, output y);
///   wire n1;
///   INV u1 (.A(a), .Y(n1), .VDD(1'b1), .VSS(1'b0));
///   DFF u2 (clk, n1, y);
/// endmodule
/// ```
const String _blackBoxJson = r'''
{"creator":"Yosys 0.69","modules":{"top":{"attributes":{"top":"00000000000000000000000000000001"},
"ports":{"a":{"direction":"input","bits":[2]},"clk":{"direction":"input",
"bits":[3]},"y":{"direction":"output","bits":[4]}},"cells":{"u1":{"hide_name":0,
"type":"INV","parameters":{},"attributes":{},"connections":{"A":[2],"VDD":["1"],
"VSS":["0"],"Y":[5]}},"u2":{"hide_name":0,"type":"DFF","parameters":{},
"attributes":{},"connections":{"$1":[3],"$2":[5],"$3":[4]}}},"netnames":{"a":{"hide_name":0,
"bits":[2],"attributes":{}},"clk":{"hide_name":0,"bits":[3],"attributes":{}},
"n1":{"hide_name":0,"bits":[5],"attributes":{}},"y":{"hide_name":0,"bits":[4],
"attributes":{}}}}}}
''';

/// Answers as Yosys does: the missing-module error under `-check`, the
/// black-box netlist without it.
class _Runner extends YosysRunner with RunBackedKeepingJson {
  final List<YosysRunRequest> requests = <YosysRunRequest>[];

  @override
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(String line)? onStderrLine,
    Map<String, String>? environment,
  }) async {
    requests.add(request);
    if (!request.allowUndefinedModules) {
      return const YosysRunFailure(
        exitCode: 1,
        stdout: '',
        stderr: _missingStderr,
        kind: YosysFailureKind.nonZeroExit,
      );
    }
    return const YosysRunSuccess(
      rawJson: _blackBoxJson,
      stdout: '',
      stderr: 'yosys says hi',
    );
  }
}

void main() {
  late Directory dir;
  late String top;
  late _Runner runner;
  late ProviderContainer container;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('netcrux_black_box_elab');
    top = p.join(dir.path, 'top.v');
    File(top).writeAsStringSync('module top(); endmodule\n');
    runner = _Runner();
    container = ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        // These tests are about the Yosys route.
        cliNetlistReaderOverrideProvider.overrideWithValue(
          NetlistReaderChoice.yosys,
        ),
        yosysRunnerProvider.overrideWith((ref) => runner),
        yosysAvailabilityProvider.overrideWith(
          (ref) async => const YosysAvailability.available(
            executablePath: '/fake/yosys',
            versionString: 'Yosys fake',
          ),
        ),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  void open({required bool blackBoxes}) {
    container
        .read(currentProjectProvider.notifier)
        .setProject(
          NetcruxProject.create(
            sourceFiles: <String>[top],
            blackBoxMissingModules: blackBoxes,
          ),
        );
  }

  test('a missing module is its own error kind, naming the module', () async {
    open(blackBoxes: false);
    await expectLater(
      container.read(loadedNetlistProvider.future),
      throwsA(
        isA<LoadedNetlistException>()
            .having((e) => e.kind, 'kind', LoadedNetlistErrorKind.missingModule)
            .having((e) => e.missingModule, 'missingModule', 'INV')
            .having((e) => e.detail, 'detail', _missingStderr),
      ),
    );
    expect(runner.requests.single.allowUndefinedModules, isFalse);
  });

  test('turning the option on elaborates without -check and infers '
      'the black-box pins', () async {
    open(blackBoxes: false);
    await expectLater(
      container.read(loadedNetlistProvider.future),
      throwsA(isA<LoadedNetlistException>()),
    );
    container
        .read(currentProjectProvider.notifier)
        .setBlackBoxMissingModules(enabled: true);
    final model = (await container.read(loadedNetlistProvider.future))!;
    expect(runner.requests, hasLength(2));
    expect(runner.requests.last.allowUndefinedModules, isTrue);

    final cells = model.modules['top']!.cells;
    expect(cells['u1']!.portDirections, <String, PortDirection>{
      'A': PortDirection.input,
      'VDD': PortDirection.input,
      'VSS': PortDirection.input,
      'Y': PortDirection.output,
    });
    expect(cells['u2']!.portDirections, <String, PortDirection>{
      r'$1': PortDirection.input,
      r'$2': PortDirection.input,
      r'$3': PortDirection.output,
    });

    final stderr = container.read(elaborationStderrProvider);
    expect(
      stderr,
      startsWith(
        'Warning: No definition found for 2 module types, drawn as black '
        'boxes with pin directions inferred from the wiring: DFF, INV.\n'
        'Warning: 1 of 7 black-box pins',
      ),
    );
    expect(stderr, endsWith('yosys says hi'));
  });

  test('the option has its own cache entry, warnings included', () async {
    open(blackBoxes: true);
    await container.read(loadedNetlistProvider.future);
    container.read(elaborationStderrProvider.notifier).set('');
    container.invalidate(loadedNetlistProvider);
    await container.read(loadedNetlistProvider.future);
    expect(runner.requests, hasLength(1));
    expect(
      container.read(elaborationStderrProvider),
      startsWith('Warning: No definition found'),
    );
  });

  test('buildRequest carries the option', () {
    final project = NetcruxProject.create(sourceFiles: const <String>['a.v']);
    expect(
      LoadedNetlist.buildRequest(project).allowUndefinedModules,
      isFalse,
    );
    expect(
      LoadedNetlist.buildRequest(
        project.copyWith(blackBoxMissingModules: true),
      ).allowUndefinedModules,
      isTrue,
    );
  });

  test('missingModuleIn reads the module name out of the message', () {
    expect(missingModuleIn(_missingStderr), 'INV');
    expect(
      missingModuleIn(
        "ERROR: Module `std_inv_x2' referenced in module "
        r"`\top' in cell `\u1' is not part of the design.",
      ),
      'std_inv_x2',
    );
    expect(missingModuleIn('ERROR: syntax error'), isNull);
  });
}
