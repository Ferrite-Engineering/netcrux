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

import '../../../helpers/run_backed_keeping_json.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// Records each request and answers with a canned netlist.
class _RecordingRunner extends YosysRunner with RunBackedKeepingJson {
  final List<YosysRunRequest> requests = <YosysRunRequest>[];

  @override
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
    Map<String, String>? environment,
    void Function(String line)? onStderrLine,
  }) async {
    requests.add(request);
    return const YosysRunSuccess(
      rawJson:
          '{"creator":"fake","modules":{"top":{"attributes":{"top":"1"},'
          '"ports":{},"cells":{},"netnames":{}}}}',
      stdout: '',
      stderr: 'yosys says hi',
    );
  }
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

void main() {
  late Directory dir;
  late String top;
  late _RecordingRunner runner;
  late ProviderContainer container;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('netcrux_liberty_elab');
    top = p.join(dir.path, 'top.v');
    File(top).writeAsStringSync('module top(); endmodule\n');
    runner = _RecordingRunner();
    container = ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        yosysRunnerProvider.overrideWith((ref) => runner),
        yosysAvailabilityProvider.overrideWith(
          (ref) async => const YosysAvailability.available(
            executablePath: '/fake/yosys',
            versionString: 'Yosys fake',
          ),
        ),
        libertyStubServiceProvider.overrideWith(
          (ref) => LibertyStubService(cacheBaseDirectory: () async => dir),
        ),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  String writeLib(String name, String text) {
    final path = p.join(dir.path, name);
    File(path).writeAsStringSync(text);
    return path;
  }

  void open(List<String> libertyFiles) {
    container
        .read(currentProjectProvider.notifier)
        .setProject(
          NetcruxProject.create(
            sourceFiles: <String>[top],
            libertyFiles: libertyFiles,
          ),
        );
  }

  test(
    'the stub file is read first, as Verilog, ahead of the sources',
    () async {
      open(<String>[writeLib('cells.lib', _cells)]);
      await container.read(loadedNetlistProvider.future);
      final sources = runner.requests.single.sources;
      expect(sources, hasLength(2));
      expect(sources.first.language, YosysSourceLanguage.verilog);
      expect(p.dirname(sources.first.path), p.join(dir.path, 'liberty-cache'));
      expect(sources.last.path, top);
      final stub = File(sources.first.path).readAsStringSync();
      expect(stub, contains('module INV (VDD, VSS, A, Y);'));
      expect(stub, contains('inout VDD;'));
    },
  );

  test('a project without cell libraries sends only its sources', () async {
    open(const <String>[]);
    await container.read(loadedNetlistProvider.future);
    expect(runner.requests.single.sources.single.path, top);
  });

  test('library warnings lead the diagnostics stderr', () async {
    final a = writeLib('a.lib', _cells);
    final b = writeLib(
      'b.lib',
      _cells.replaceAll('library (cells)', 'library (b)'),
    );
    open(<String>[a, b]);
    await container.read(loadedNetlistProvider.future);
    final stderr = container.read(elaborationStderrProvider);
    expect(stderr, startsWith('Warning: Cell "INV" is defined in both'));
    expect(stderr, endsWith('yosys says hi'));
  });

  test('an unchanged library is a cache hit; a changed one re-runs', () async {
    final lib = writeLib('cells.lib', _cells);
    open(<String>[lib]);
    await container.read(loadedNetlistProvider.future);
    container.invalidate(loadedNetlistProvider);
    await container.read(loadedNetlistProvider.future);
    expect(runner.requests, hasLength(1));

    File(lib).setLastModifiedSync(DateTime(2001));
    container.invalidate(loadedNetlistProvider);
    await container.read(loadedNetlistProvider.future);
    expect(runner.requests, hasLength(2));
  });

  test('a malformed library is skipped and warned about, not fatal', () async {
    final bad = writeLib('bad.lib', 'library (x) {\n  cell (A) {\n');
    final good = writeLib('cells.lib', _cells);
    open(<String>[bad, good]);
    final result = await container.read(loadedNetlistProvider.future);
    expect(result, isNotNull);
    final sources = runner.requests.single.sources;
    expect(
      File(sources.first.path).readAsStringSync(),
      contains('module INV'),
    );
    final stderr = container.read(elaborationStderrProvider);
    expect(stderr, startsWith('Warning: Cell library skipped'));
    expect(stderr, contains(bad));
    expect(stderr, contains('line'));
    expect(stderr, endsWith('yosys says hi'));
  });

  test('a missing library is skipped and warned about, not fatal', () async {
    final missing = p.join(dir.path, 'missing.lib');
    open(<String>[missing]);
    final result = await container.read(loadedNetlistProvider.future);
    expect(result, isNotNull);
    expect(runner.requests, hasLength(1));
    final stderr = container.read(elaborationStderrProvider);
    expect(stderr, startsWith('Warning: Cell library skipped'));
    expect(stderr, contains(missing));
  });

  test('buildRequest puts the stub ahead of every source', () {
    final request = LoadedNetlist.buildRequest(
      NetcruxProject.create(sourceFiles: const <String>['a.sv', 'b.v']),
      libertyStubPath: '/cache/stubs.v',
    );
    expect(request.sources.map((s) => s.path), <String>[
      '/cache/stubs.v',
      'a.sv',
      'b.v',
    ]);
    expect(request.sources.first.language, YosysSourceLanguage.verilog);
  });
}
