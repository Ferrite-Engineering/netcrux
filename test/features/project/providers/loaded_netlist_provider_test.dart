// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_runner_provider.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// Counts `run()` invocations and returns a canned `write_json` success —
/// so the elaboration-cache tests can assert whether the pipeline
/// actually spawned "yosys" or served the parsed model from the cache.
class _CountingRunner extends YosysRunner {
  _CountingRunner(this.rawJson);

  final String rawJson;
  int calls = 0;
  YosysRunRequest? lastRequest;

  @override
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(String line)? onStderrLine,
  }) async {
    calls++;
    lastRequest = request;
    return YosysRunSuccess(
      rawJson: rawJson,
      stdout: '',
      stderr: 'warn: run $calls',
    );
  }
}

const String _fakeRawJson =
    '{"creator":"fake yosys","modules":{"top":{"attributes":{"top":"1"}, '
    '"ports":{},"cells":{},"netnames":{}}}}';

void main() {
  group('LoadedNetlistException', () {
    test('toString includes the message and cause', () {
      const e = LoadedNetlistException('boom', cause: 'because');
      expect(e.toString(), contains('boom'));
      expect(e.toString(), contains('because'));
    });

    test('toString without cause has only the message', () {
      const e = LoadedNetlistException('alone');
      expect(e.toString(), contains('alone'));
      expect(e.toString(), isNot(contains('cause')));
    });
  });

  group('loadedNetlistProvider', () {
    test('resolves to null when no source files are pending', () async {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      final model = await container.read(loadedNetlistProvider.future);
      expect(model, isNull);
    });

    test('setModel overrides the AsyncValue without spawning yosys', () {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      const model = NetlistModel(
        creator: 'override',
        modules: <String, Module>{},
      );
      container.read(loadedNetlistProvider.notifier).setModel(model);
      expect(
        container.read(loadedNetlistProvider).value,
        same(model),
      );
    });

    test(
      're-elaboration with unchanged inputs is served from the cache',
      () async {
        final dir = Directory.systemTemp.createTempSync('netcrux_elab_hit_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final src = File('${dir.path}/top.v')
          ..writeAsStringSync('module top(); endmodule\n');
        final runner = _CountingRunner(_fakeRawJson);
        final container = ProviderContainer(
          overrides: [
            ...netcruxTelemetryTestOverrides(),
            yosysRunnerProvider.overrideWith((ref) => runner),
            yosysAvailabilityProvider.overrideWith(
              (ref) async => const YosysAvailability.available(
                executablePath: '/fake/yosys',
                versionString: 'Yosys fake',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(currentProjectProvider.notifier).setSourceFiles(<String>[
          src.path,
        ]);

        final first = await container.read(loadedNetlistProvider.future);
        expect(first?.topModule?.name, 'top');
        expect(runner.calls, 1);
        expect(container.read(elaborationStderrProvider), 'warn: run 1');

        // Same inputs → the rebuild is a cache hit: no second spawn, the
        // SAME parsed model instance, and the cached run's stderr restored
        // so the diagnostics drawer matches a live run.
        container.read(elaborationStderrProvider.notifier).set('');
        container.invalidate(loadedNetlistProvider);
        final second = await container.read(loadedNetlistProvider.future);
        expect(runner.calls, 1, reason: 'unchanged inputs must hit the cache');
        expect(second, same(first));
        expect(container.read(elaborationStderrProvider), 'warn: run 1');

        // Touching the source (different byte size → different fingerprint,
        // no mtime-resolution dependence) misses and re-spawns.
        src.writeAsStringSync('module top(); /* changed */ endmodule\n');
        container.invalidate(loadedNetlistProvider);
        await container.read(loadedNetlistProvider.future);
        expect(runner.calls, 2, reason: 'a changed source must miss the cache');
      },
    );
  });

  group('loadedNetlistProvider — pre-built netlist', () {
    const seedNetlist =
        'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json';

    /// A container whose Yosys runner and availability probe both fail the
    /// test if the pipeline touches them.
    ProviderContainer yosysForbidden({List<Override> extra = const []}) {
      final runner = _CountingRunner(_fakeRawJson);
      final container = ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          yosysRunnerProvider.overrideWith((ref) => runner),
          yosysAvailabilityProvider.overrideWith(
            (ref) async => fail('a netlist load must not probe for Yosys'),
          ),
          ...extra,
        ],
      );
      addTearDown(() {
        expect(runner.calls, 0, reason: 'a netlist load must not run Yosys');
        container.dispose();
      });
      return container;
    }

    test('a .json source is parsed directly, without Yosys', () async {
      final container = yosysForbidden();
      container.read(currentProjectProvider.notifier).setSourceFiles(<String>[
        File(seedNetlist).absolute.path,
      ]);
      final model = await container.read(loadedNetlistProvider.future);
      expect(model?.topModule?.name, 'top');
      expect(model?.modules.keys, containsAll(<String>['cpu', 'alu']));
    });

    test('a missing netlist file is a load error, not a Yosys error', () async {
      final container = yosysForbidden();
      container.read(currentProjectProvider.notifier).setSourceFiles(<String>[
        '/no/such/netlist.json',
      ]);
      await expectLater(
        container.read(loadedNetlistProvider.future),
        throwsA(
          isA<LoadedNetlistException>().having(
            (e) => e.kind,
            'kind',
            LoadedNetlistErrorKind.unknown,
          ),
        ),
      );
    });

    test(
      'a build that cannot elaborate reads any single location as a netlist',
      () async {
        final raw = File(seedNetlist).readAsStringSync();
        final read = <String>[];
        final container = yosysForbidden(
          extra: [
            hdlElaborationSupportedProvider.overrideWithValue(false),
            prebuiltNetlistLoaderProvider.overrideWithValue(
              PrebuiltNetlistLoader(
                read: (location) async {
                  read.add(location);
                  return raw;
                },
                parseOnIsolate: false,
              ),
            ),
          ],
        );
        const url = 'https://example.com/netlist?id=7';
        container.read(currentProjectProvider.notifier).setSourceFiles(
          const <String>[url],
        );
        final model = await container.read(loadedNetlistProvider.future);
        expect(read, <String>[url]);
        expect(model?.topModule?.name, 'top');
      },
    );

    test(
      'a build that cannot elaborate reports HDL sources as unavailable',
      () async {
        final container = yosysForbidden(
          extra: [hdlElaborationSupportedProvider.overrideWithValue(false)],
        );
        container.read(currentProjectProvider.notifier).setSourceFiles(
          const <String>['/d/a.v', '/d/b.v'],
        );
        await expectLater(
          container.read(loadedNetlistProvider.future),
          throwsA(
            isA<LoadedNetlistException>().having(
              (e) => e.kind,
              'kind',
              LoadedNetlistErrorKind.yosysUnavailable,
            ),
          ),
        );
      },
    );
  });

  group('loadDesignNetlist — a design outside any tab', () {
    const seedNetlist =
        'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json';

    Future<NetlistModel?> load(
      ProviderContainer container,
      NetcruxProject project,
    ) {
      // No automatic retry, or a failure would sit in loading while Riverpod
      // backs off and retries.
      final probe = FutureProvider<NetlistModel?>(
        (ref) => loadDesignNetlist(ref, project),
        retry: noElaborationRetry,
      );
      // Held open so the probe is not disposed while its load is in flight.
      final subscription = container.listen(probe, (_, _) {});
      addTearDown(subscription.close);
      return container.read(probe.future);
    }

    test('a .json design is parsed without Yosys', () async {
      final runner = _CountingRunner(_fakeRawJson);
      final container = ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          yosysRunnerProvider.overrideWith((ref) => runner),
          yosysAvailabilityProvider.overrideWith(
            (ref) async => fail('a netlist load must not probe for Yosys'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final model = await load(
        container,
        NetcruxProject.create(
          sourceFiles: <String>[File(seedNetlist).absolute.path],
        ),
      );
      expect(model?.topModule?.name, 'top');
      expect(runner.calls, 0);
    });

    test('HDL sources are elaborated with the knobs they are given', () async {
      final dir = Directory.systemTemp.createTempSync('netcrux_design_once_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final a = File('${dir.path}/a.v')
        ..writeAsStringSync('module a(); endmodule');
      final b = File('${dir.path}/b.v')
        ..writeAsStringSync('module b(); endmodule');
      final runner = _CountingRunner(_fakeRawJson);
      final container = ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          yosysRunnerProvider.overrideWith((ref) => runner),
          yosysAvailabilityProvider.overrideWith(
            (ref) async => const YosysAvailability.available(
              executablePath: '/fake/yosys',
              versionString: 'Yosys fake',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final model = await load(
        container,
        NetcruxProject.create(
          sourceFiles: <String>[a.path, b.path],
          topModule: 'top',
          defines: const <String, String>{'WIDTH': '8'},
        ),
      );
      expect(model?.topModule?.name, 'top');
      expect(runner.calls, 1);
      expect(runner.lastRequest?.sources.map((s) => s.path), <String>[
        a.path,
        b.path,
      ]);
      expect(runner.lastRequest?.topModule, 'top');
      expect(runner.lastRequest?.defines, <String>['WIDTH=8']);
      // Not the tab's design: no stderr is published into the tab.
      expect(container.read(elaborationStderrProvider), isEmpty);
    });

    test('no Yosys is reported as the missing engine', () async {
      final container = ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          yosysAvailabilityProvider.overrideWith(
            (ref) async => const YosysAvailability.notFound(reason: 'gone'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await expectLater(
        load(
          container,
          NetcruxProject.create(sourceFiles: const <String>['/d/a.v']),
        ),
        throwsA(
          isA<LoadedNetlistException>().having(
            (e) => e.kind,
            'kind',
            LoadedNetlistErrorKind.yosysUnavailable,
          ),
        ),
      );
    });
  });

  group('LoadedNetlist.buildRequest', () {
    test('classifies a pure-Verilog project as Verilog sources', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.v', 'sub.v'],
        topModule: 'top',
      );
      final request = LoadedNetlist.buildRequest(project);
      expect(request.sources, hasLength(2));
      for (final source in request.sources) {
        expect(source.language, YosysSourceLanguage.verilog);
      }
      expect(request.hasVhdlSources, isFalse);
      expect(request.vhdlStandard, isNull);
      expect(request.vhdlTopUnit, 'top');
    });

    test('classifies a .vhd source as VHDL via extension auto-detect', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.vhd'],
        topModule: 'top',
      );
      final request = LoadedNetlist.buildRequest(project);
      expect(request.sources.single.language, YosysSourceLanguage.vhdl);
      expect(request.hasVhdlSources, isTrue);
    });

    test('honors an explicit override against the file extension', () {
      // `.v` extension but the user marked it as SystemVerilog —
      // the override wins over auto-detection.
      final project = NetcruxProject.create(
        sourceFiles: const <String>['legacy.v'],
        sourceFileLanguages: const <String, NetcruxSourceLanguage>{
          'legacy.v': NetcruxSourceLanguage.systemVerilog,
        },
      );
      final request = LoadedNetlist.buildRequest(project);
      expect(
        request.sources.single.language,
        YosysSourceLanguage.systemVerilog,
      );
    });

    test('mixed Verilog + VHDL sources produce a mixed request', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.v', 'sub.vhd'],
        topModule: 'top',
      );
      final request = LoadedNetlist.buildRequest(project);
      expect(request.hasVerilogSources, isTrue);
      expect(request.hasVhdlSources, isTrue);
      expect(request.sources[0].language, YosysSourceLanguage.verilog);
      expect(request.sources[1].language, YosysSourceLanguage.vhdl);
    });

    test('a VHDL project sets vhdlTopUnit to the top module', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.vhd'],
        topModule: 'top',
      );
      final request = LoadedNetlist.buildRequest(project);
      expect(request.hasVhdlSources, isTrue);
      expect(request.vhdlTopUnit, 'top');
    });

    test('empty top module is preserved as null on the request', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.v'],
      );
      final request = LoadedNetlist.buildRequest(project);
      expect(request.topModule, isNull);
      expect(request.vhdlTopUnit, isNull);
    });

    test('defines map → list conversion preserves bare-flag entries', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.v'],
        defines: const <String, String>{
          'WIDTH': '32',
          'FAST': '',
          'DEBUG': '',
        },
      );
      final request = LoadedNetlist.buildRequest(project);
      expect(request.defines, contains('WIDTH=32'));
      expect(request.defines, contains('FAST'));
      expect(request.defines, contains('DEBUG'));
      expect(request.defines, isNot(contains('FAST=')));
    });
  });
}
