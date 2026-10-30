// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netlist_reader_choice.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/project/providers/netlist_reader_run_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/liberty/liberty_stub_service.dart';
import 'package:netcrux/services/liberty/liberty_stub_service_provider.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:netcrux/services/yosys/netlist_reader_provider.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_runner_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/run_backed_keeping_json.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// Answers like Yosys and counts how often it is asked.
class _CountingRunner extends YosysRunner with RunBackedKeepingJson {
  int calls = 0;

  @override
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
    Map<String, String>? environment,
    void Function(String line)? onStderrLine,
  }) async {
    calls++;
    return const YosysRunSuccess(
      rawJson:
          '{"creator":"fake yosys","modules":{"top":{"attributes":'
          ' {"top":"1"},"ports":{},"cells":{},"netnames":{}}}}',
      stdout: '',
      stderr: 'yosys says hi',
    );
  }
}

const String _netlist = '''
module top (input a, output y);
  wire n;
  INV u1 (.A(a), .Y(n));
  INV u2 (.A(n), .Y(y));
endmodule
''';

const String _rtl = '''
module top (input a, output y);
  always @(a) begin end
endmodule
''';

const String _library = '''
library (cells) {
  cell (INV) {
    pin (A) { direction : input ; }
    pin (Y) { direction : output ; }
  }
}
''';

void main() {
  late Directory dir;
  late _CountingRunner runner;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('netcrux_native_load');
    runner = _CountingRunner();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, String text) {
    final path = p.join(dir.path, name);
    File(path).writeAsStringSync(text);
    return path;
  }

  Future<ProviderContainer> container({
    bool settingOn = true,
    NetlistReaderChoice? cli,
    bool yosysAvailable = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'netcrux.nativeGateLevelReader': settingOn,
    });
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        settingsServiceProvider.overrideWithValue(
          SettingsService<AppSettings>(
            const NetcruxSettingsCodec(),
            prefsOverride: prefs,
          ),
        ),
        cliNetlistReaderOverrideProvider.overrideWithValue(cli),
        yosysRunnerProvider.overrideWith((ref) => runner),
        yosysAvailabilityProvider.overrideWith(
          (ref) async => yosysAvailable
              ? const YosysAvailability.available(
                  executablePath: '/fake/yosys',
                  versionString: 'Yosys fake',
                )
              : const YosysAvailability.notFound(),
        ),
        libertyStubServiceProvider.overrideWith(
          (ref) => LibertyStubService(cacheBaseDirectory: () async => dir),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<NetlistModel?> open(ProviderContainer c, NetcruxProject project) {
    c.read(currentProjectProvider.notifier).setProject(project);
    return c.read(loadedNetlistProvider.future);
  }

  test(
    'a gate-level netlist is read natively, without running Yosys',
    () async {
      final top = write('top.v', _netlist);
      final lib = write('cells.lib', _library);
      final c = await container(yosysAvailable: false);
      final model = await open(
        c,
        NetcruxProject.create(sourceFiles: [top], libertyFiles: [lib]),
      );
      expect(model!.creator, 'NetCrux native gate-level reader');
      expect(model.topModule?.name, 'top');
      expect(model.topModule!.cells.keys, ['u1', 'u2']);
      expect(runner.calls, 0);
      final stderr = c.read(elaborationStderrProvider);
      expect(stderr, startsWith('Info: Netlist read by the native gate-level'));
      expect(stderr, contains('Yosys was not run'));
      expect(
        c.read(netlistReaderRunProvider),
        const NetlistReaderRun(NetlistReaderKind.native),
      );
    },
  );

  test('with the setting off, Yosys reads the design and says so', () async {
    final top = write('top.v', _netlist);
    final c = await container(settingOn: false);
    await open(c, NetcruxProject.create(sourceFiles: [top]));
    expect(runner.calls, 1);
    final stderr = c.read(elaborationStderrProvider);
    expect(
      stderr,
      startsWith(
        'Info: Netlist read by Yosys (the native gate-level reader is turned '
        'off in Settings > Engines).',
      ),
    );
    expect(
      c.read(netlistReaderRunProvider),
      const NetlistReaderRun(NetlistReaderKind.yosys),
    );
  });

  group('precedence: command line, then project, then setting', () {
    test('the command line forces Yosys over the setting', () async {
      final top = write('top.v', _netlist);
      final c = await container(cli: NetlistReaderChoice.yosys);
      await open(c, NetcruxProject.create(sourceFiles: [top]));
      expect(runner.calls, 1);
      expect(
        c.read(elaborationStderrProvider),
        contains('turned off with --netlist-reader'),
      );
    });

    test(
      'the command line forces native over a project that says Yosys',
      () async {
        final top = write('top.v', _netlist);
        final c = await container(cli: NetlistReaderChoice.native);
        await open(
          c,
          NetcruxProject.create(
            sourceFiles: [top],
            netlistReader: NetlistReaderChoice.yosys,
          ),
        );
        expect(runner.calls, 0);
      },
    );

    test('a project can turn the reader off or on over the setting', () async {
      final top = write('top.v', _netlist);
      final off = await container();
      await open(
        off,
        NetcruxProject.create(
          sourceFiles: [top],
          netlistReader: NetlistReaderChoice.yosys,
        ),
      );
      expect(runner.calls, 1);
      expect(
        off.read(elaborationStderrProvider),
        contains("turned off by the project's netlistReader key"),
      );

      final on = await container(settingOn: false);
      await open(
        on,
        NetcruxProject.create(
          sourceFiles: [top],
          netlistReader: NetlistReaderChoice.native,
        ),
      );
      expect(runner.calls, 1, reason: 'the native reader ran, not Yosys');
    });
  });

  group('fallback to Yosys', () {
    test(
      'RTL the reader does not read names the construct and the line',
      () async {
        final top = write('top.v', _rtl);
        final c = await container();
        await open(c, NetcruxProject.create(sourceFiles: [top]));
        expect(runner.calls, 1);
        final stderr = c.read(elaborationStderrProvider);
        final lines = stderr.split('\n');
        expect(
          lines.first,
          '$top:2: Warning: The native gate-level reader uses an `always` block, '
          'which it does not read; Yosys reads this design instead.',
        );
        expect(lines[1], contains('Info: Netlist read by Yosys'));
        expect(lines.last, 'yosys says hi');
        expect(
          c.read(netlistReaderRunProvider),
          const NetlistReaderRun(NetlistReaderKind.yosys, fellBack: true),
        );
        // The line is a Diagnostics entry with a file and a line to go to.
        final entry = c
            .read(elaborationDiagnosticsProvider)
            .firstWhere((d) => d.line == 2);
        expect(entry.filePath, top);
      },
    );

    test('with no Yosys either, Diagnostics still says why', () async {
      final top = write('top.v', _rtl);
      final c = await container(yosysAvailable: false);
      c
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(sourceFiles: [top]),
          );
      await expectLater(
        c.read(loadedNetlistProvider.future),
        throwsA(isA<LoadedNetlistException>()),
      );
      expect(
        c.read(elaborationStderrProvider),
        contains('an `always` block'),
      );
    });

    test(
      'a SystemVerilog source is not offered to the native reader',
      () async {
        final top = write('top.sv', _netlist);
        final c = await container();
        await open(c, NetcruxProject.create(sourceFiles: [top]));
        expect(runner.calls, 1);
        expect(
          c.read(elaborationStderrProvider),
          contains('does not apply: it reads Verilog netlists only'),
        );
      },
    );

    test('a project that runs extra Yosys commands keeps Yosys', () async {
      final top = write('top.v', _netlist);
      final c = await container();
      await open(
        c,
        NetcruxProject.create(
          sourceFiles: [top],
          extraYosysCommands: const ['flatten'],
        ),
      );
      expect(runner.calls, 1);
      expect(
        c.read(elaborationStderrProvider),
        contains('runs extra Yosys commands'),
      );
    });
  });

  test('cell model files give the pins their directions', () async {
    final top = write('top.v', _netlist);
    final models = write('models.v', '''
(* blackbox *)
module INV (input A, output Y);
endmodule
''');
    final c = await container(yosysAvailable: false);
    final model = await open(
      c,
      NetcruxProject.create(sourceFiles: [top], cellModelFiles: [models]),
    );
    final u1 = model!.topModule!.cells['u1']!;
    expect(u1.portDirections, {
      'A': PortDirection.input,
      'Y': PortDirection.output,
    });
    expect(model.modules['INV']!.isBlackBox, isTrue);
  });

  test('an unchanged design is served from the cache', () async {
    final top = write('top.v', _netlist);
    final c = await container(yosysAvailable: false);
    final first = await open(c, NetcruxProject.create(sourceFiles: [top]));
    c.invalidate(loadedNetlistProvider);
    final second = await c.read(loadedNetlistProvider.future);
    expect(second, same(first));
    expect(
      c.read(elaborationStderrProvider),
      startsWith('Info: Netlist read by the native'),
    );
  });

  test('a design that changed is read again', () async {
    final top = write('top.v', _netlist);
    final c = await container(yosysAvailable: false);
    final first = await open(c, NetcruxProject.create(sourceFiles: [top]));
    File(top).writeAsStringSync('$_netlist\n// changed\n');
    c.invalidate(loadedNetlistProvider);
    final second = await c.read(loadedNetlistProvider.future);
    expect(second, isNot(same(first)));
  });

  test('Cancel stops a native read and leaves no model', () async {
    final text = StringBuffer('module top (input a);\n');
    for (var i = 0; i < 300000; i++) {
      text.writeln('  INV u$i (.A(a), .Y(n$i));');
    }
    text.writeln('endmodule');
    final top = write('top.v', '$text');
    final c = await container(yosysAvailable: false);
    c
        .read(currentProjectProvider.notifier)
        .setProject(
          NetcruxProject.create(sourceFiles: [top]),
        );
    final pending = c.read(loadedNetlistProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final clock = Stopwatch()..start();
    c.read(loadedNetlistProvider.notifier).cancelElaboration();
    expect(await pending, isNull);
    expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    expect(runner.calls, 0);
  });

  test('a gzip-compressed netlist is read natively', () async {
    final gz = p.join(dir.path, 'top.v.gz');
    File(gz).writeAsBytesSync(gzip.encode(_netlist.codeUnits));
    final c = await container(yosysAvailable: false);
    final model = await open(c, NetcruxProject.create(sourceFiles: [gz]));
    expect(model!.topModule!.cells, hasLength(2));
    expect(runner.calls, 0);
  });
}
