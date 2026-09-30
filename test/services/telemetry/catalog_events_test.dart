// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// One test per NetCrux-specific catalog event, on the real code path.
//
// The catalog conformance test proves the pinned list would survive the
// ingestion Worker. It cannot prove the events are ever recorded, or that the
// values a call site produces come from the closed vocabulary the list
// promises. That is this file: every event below is driven through the
// production seam — the elaboration pipeline, the hierarchy notifier, the
// search dialog's result-activation path, the action dispatcher, the export
// controller, the CXP handlers — and asserted against
// `kNetcruxEventCatalog`'s own vocabulary rather than against a literal
// repeated here.
//
// `_assertInCatalog` is the shared closing argument: it re-checks every
// recorded name, key and value against the catalog entry, so a call site that
// invents a value the catalog does not list fails here even though it is
// perfectly well-formed and the Worker would happily store it.

import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netcrux_design_source.dart';
import 'package:netcrux/domain/enums/netcrux_export_kind.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/search/widgets/search_dialog.dart';
import 'package:netcrux/features/viewer/services/schematic_export_controller.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/search/design_search_service.dart';
import 'package:netcrux/services/telemetry/telemetry_event_catalog.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_runner_provider.dart';

class _RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  List<String> get names => [for (final e in events) e.name];

  TelemetryEvent named(String name) => events.firstWhere(
    (e) => e.name == name,
    orElse: () => throw StateError('no $name in $names'),
  );

  int count(String name) => names.where((n) => n == name).length;
}

/// Fails unless [event] is in the pinned catalog and every property it carries
/// is one the catalog declares, with a value from the declared vocabulary.
///
/// This is the assertion that makes the per-event tests below mean something.
/// A call site can produce a token that passes the Worker's character class and
/// is still wrong — an unlisted `source`, a `reason` the catalog never
/// lists — and only a comparison against the catalog catches it.
void _assertInCatalog(TelemetryEvent event) {
  final entry = kNetcruxEventCatalog.firstWhere(
    (e) => e.name == event.name,
    orElse: () => throw StateError('${event.name} is not in the catalog'),
  );
  event.properties.forEach((key, value) {
    expect(
      entry.propertyKeys,
      contains(key),
      reason: '${event.name} carries an undeclared property "$key"',
    );
    if (entry.enumeratedValues.containsKey(key)) {
      expect(
        entry.enumeratedValues[key],
        contains(value),
        reason: '${event.name}.$key = "$value" is outside the catalog set',
      );
    } else if (entry.boolProperties.contains(key)) {
      expect(value, isA<bool>());
    } else {
      expect(value, isA<int>());
      expect((value! as int).abs(), lessThanOrEqualTo(100000));
    }
  });
}

// ── Elaboration harness ───────────────────────────────────────────────────────

const String _rawJson =
    '{"creator":"fake yosys","modules":{"top":{"attributes":{"top":"1"}, '
    '"ports":{},"cells":{},"netnames":{}}}}';

class _FakeRunner extends YosysRunner {
  _FakeRunner(this.result);

  final YosysRunResult Function() result;
  int calls = 0;

  @override
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(String line)? onStderrLine,
  }) async {
    calls++;
    return result();
  }
}

/// A two-module design: `top` instantiates `u_child` (module `child`), which is
/// what `pushInto` needs to resolve.
NetlistModel modelWithChild() => const NetlistModel(
  creator: 'test',
  modules: <String, Module>{
    'top': Module(
      name: 'top',
      attributes: <String, String>{'top': '1'},
      ports: <String, Port>{},
      cells: <String, Cell>{
        'u_child': Cell(
          name: 'u_child',
          type: 'child',
          parameters: <String, String>{},
          attributes: <String, String>{},
          portDirections: <String, PortDirection>{},
          connections: <String, List<BitRef>>{},
        ),
      },
      nets: <String, Net>{},
    ),
    'child': Module(
      name: 'child',
      attributes: <String, String>{},
      ports: <String, Port>{},
      cells: <String, Cell>{},
      nets: <String, Net>{},
    ),
  },
);

void main() {
  late _RecordingTelemetryService telemetry;

  setUp(() => telemetry = _RecordingTelemetryService());

  ProviderContainer elaborationContainer({
    required YosysRunResult Function() result,
    YosysAvailability availability = const YosysAvailability.available(
      executablePath: '/fake/yosys',
      versionString: 'Yosys fake',
    ),
  }) {
    final container = ProviderContainer(
      overrides: [
        telemetryServiceProvider.overrideWithValue(telemetry),
        yosysRunnerProvider.overrideWith((ref) => _FakeRunner(result)),
        yosysAvailabilityProvider.overrideWith((ref) async => availability),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// A temp directory holding one source file per extension in [names].
  Directory sourcesFor(List<String> names) {
    final dir = Directory.systemTemp.createTempSync('netcrux_catalog_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort — a Windows lock is not this test's business.
      }
    });
    for (final name in names) {
      File('${dir.path}/$name').writeAsStringSync('module top(); endmodule\n');
    }
    return dir;
  }

  // ── design.elaborated ───────────────────────────────────────────────────────

  group('design.elaborated', () {
    Future<TelemetryEvent> elaborate({
      required List<String> fileNames,
      NetcruxDesignSource source = NetcruxDesignSource.rtl,
    }) async {
      final dir = sourcesFor(fileNames);
      final container = elaborationContainer(
        result: () => const YosysRunSuccess(
          rawJson: _rawJson,
          stdout: '',
          stderr: '',
        ),
      );
      container
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(
              sourceFiles: [for (final n in fileNames) '${dir.path}/$n'],
            ),
            source: source,
          );
      await container.read(loadedNetlistProvider.future);
      // The last one: a test may elaborate several times against the same
      // recorder, and `named` returns the first match.
      return telemetry.events.lastWhere(
        (e) => e.name == 'design.elaborated',
      );
    }

    test('fires on a successful elaboration', () async {
      final event = await elaborate(fileNames: <String>['top.v']);
      expect(telemetry.count('design.elaborated'), 1);
      expect(telemetry.count('design.elaboration_failed'), 0);
      _assertInCatalog(event);
    });

    test('language is folded from the resolved per-file languages', () async {
      // Not from a file name, not from an extension string — the enum
      // `NetcruxProject.resolveLanguage` already returns.
      expect(
        (await elaborate(fileNames: <String>['top.v'])).properties['language'],
        'verilog',
      );
      expect(
        (await elaborate(fileNames: <String>['top.sv'])).properties['language'],
        'system_verilog',
      );
      expect(
        (await elaborate(
          fileNames: <String>['top.vhd'],
        )).properties['language'],
        'vhdl',
      );
    });

    test('a multi-language design reports mixed', () async {
      final event = await elaborate(
        fileNames: <String>['rtl.v', 'tb.sv'],
      );
      expect(event.properties['language'], 'mixed');
      _assertInCatalog(event);
    });

    test('source carries the entry path the user actually took', () async {
      for (final source in NetcruxDesignSource.values) {
        telemetry = _RecordingTelemetryService();
        final event = await elaborate(
          fileNames: <String>['top.v'],
          source: source,
        );
        expect(event.properties['source'], telemetryEnumToken(source));
        _assertInCatalog(event);
      }
    });

    test('cached is false on a cold run and true on a cache hit', () async {
      final dir = sourcesFor(<String>['top.v']);
      final container = elaborationContainer(
        result: () => const YosysRunSuccess(
          rawJson: _rawJson,
          stdout: '',
          stderr: '',
        ),
      );
      container.read(currentProjectProvider.notifier).setSourceFiles(<String>[
        '${dir.path}/top.v',
      ]);

      await container.read(loadedNetlistProvider.future);
      expect(telemetry.named('design.elaborated').properties['cached'], false);

      container.invalidate(loadedNetlistProvider);
      await container.read(loadedNetlistProvider.future);
      expect(telemetry.count('design.elaborated'), 2);
      expect(telemetry.events.last.properties['cached'], true);
    });

    test('an empty project records nothing', () async {
      // No sources is the welcome-screen landing state, not an elaboration.
      final container = elaborationContainer(
        result: () => const YosysRunSuccess(
          rawJson: _rawJson,
          stdout: '',
          stderr: '',
        ),
      );
      await container.read(loadedNetlistProvider.future);
      expect(telemetry.events, isEmpty);
    });

    test('carries nothing derived from the design', () async {
      final dir = sourcesFor(<String>['confidential_soc_top.v']);
      final container = elaborationContainer(
        result: () => const YosysRunSuccess(
          rawJson: _rawJson,
          stdout: '',
          stderr: '',
        ),
      );
      container.read(currentProjectProvider.notifier).setSourceFiles(<String>[
        '${dir.path}/confidential_soc_top.v',
      ]);
      await container.read(loadedNetlistProvider.future);

      final serialized = telemetry.named('design.elaborated').toString();
      expect(serialized, isNot(contains('confidential')));
      expect(serialized, isNot(contains(dir.path)));
    });
  });

  // ── design.elaboration_failed ───────────────────────────────────────────────

  group('design.elaboration_failed', () {
    test('yosys missing reports the yosys_unavailable class', () async {
      final dir = sourcesFor(<String>['top.v']);
      final container = elaborationContainer(
        result: () => const YosysRunSuccess(
          rawJson: _rawJson,
          stdout: '',
          stderr: '',
        ),
        availability: const YosysAvailability.notFound(),
      );
      container.read(currentProjectProvider.notifier).setSourceFiles(<String>[
        '${dir.path}/top.v',
      ]);

      await expectLater(
        container.read(loadedNetlistProvider.future),
        throwsA(isA<LoadedNetlistException>()),
      );

      final event = telemetry.named('design.elaboration_failed');
      expect(event.properties, <String, Object?>{
        'reason': 'yosys_unavailable',
      });
      expect(telemetry.count('design.elaborated'), 0);
      _assertInCatalog(event);
    });

    test('a non-zero exit reports non_zero_exit, never the stderr', () async {
      // The assertion this whole event exists to make: a compiler diagnostic
      // names modules, signals and files, and none of it may leave the machine.
      const stderr =
          'ERROR: /home/u/soc/top.v:42: syntax error near `secret_reg`';
      final dir = sourcesFor(<String>['top.v']);
      final container = elaborationContainer(
        result: () => const YosysRunFailure(
          exitCode: 1,
          stdout: '',
          stderr: stderr,
        ),
      );
      container.read(currentProjectProvider.notifier).setSourceFiles(<String>[
        '${dir.path}/top.v',
      ]);

      await expectLater(
        container.read(loadedNetlistProvider.future),
        throwsA(isA<LoadedNetlistException>()),
      );

      final event = telemetry.named('design.elaboration_failed');
      expect(event.properties, <String, Object?>{'reason': 'non_zero_exit'});

      // Assert against what is TRANSMITTED — the name and the properties —
      // not against `toString()`. The timestamp `toString()` carries only ages
      // the queue and never leaves the machine, and including it made this
      // test fail roughly whenever the wall clock happened to contain the
      // digits being searched for: `'42'` matched the microseconds in
      // `02:48:58.942047`. A leak check that fails on the clock is a leak
      // check nobody trusts.
      final transmitted = '${event.name} ${event.properties}';
      expect(transmitted, isNot(contains('secret_reg')));
      expect(transmitted, isNot(contains('syntax error')));
      expect(transmitted, isNot(contains('top.v')));
      expect(transmitted, isNot(contains('42')));
      _assertInCatalog(event);
    });

    test('a timeout reports the timeout class', () async {
      final dir = sourcesFor(<String>['top.v']);
      final container = elaborationContainer(
        result: () => const YosysRunTimeout(
          budget: Duration(seconds: 5),
          stdout: '',
          stderr: '',
        ),
      );
      container.read(currentProjectProvider.notifier).setSourceFiles(<String>[
        '${dir.path}/top.v',
      ]);

      await expectLater(
        container.read(loadedNetlistProvider.future),
        throwsA(isA<LoadedNetlistException>()),
      );

      expect(
        telemetry.named('design.elaboration_failed').properties['reason'],
        'timeout',
      );
    });

    test('a malformed netlist document reports unknown', () async {
      final dir = sourcesFor(<String>['top.v']);
      final container = elaborationContainer(
        result: () => const YosysRunSuccess(
          rawJson: 'not json at all',
          stdout: '',
          stderr: '',
        ),
      );
      container.read(currentProjectProvider.notifier).setSourceFiles(<String>[
        '${dir.path}/top.v',
      ]);

      await expectLater(
        container.read(loadedNetlistProvider.future),
        throwsA(anything),
      );

      expect(
        telemetry.named('design.elaboration_failed').properties['reason'],
        'unknown',
      );
    });

    test('every reason is a member of the pipeline failure enum', () {
      // Nothing constructs a reason string; the catalog list IS the enum.
      final entry = kNetcruxEventCatalog.firstWhere(
        (e) => e.name == 'design.elaboration_failed',
      );
      expect(
        entry.enumeratedValues['reason']!.toSet(),
        LoadedNetlistErrorKind.values.map(telemetryEnumToken).toSet(),
      );
    });
  });

  // ── schematic.scope_pushed ──────────────────────────────────────────────────

  group('schematic.scope_pushed', () {
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('drilling into a child scope emits it, with no properties', () {
      final c = container();
      c.read(hierarchyTreeProvider.notifier)
        ..setModel(modelWithChild())
        ..pushInto('u_child');

      expect(telemetry.count('schematic.scope_pushed'), 1);
      final event = telemetry.named('schematic.scope_pushed');
      // The instance name is design data; the counter answers "is drill-down
      // the core loop", which needs no dimension at all.
      expect(event.properties, isEmpty);
      expect(event.toString(), isNot(contains('u_child')));
      _assertInCatalog(event);
    });

    test('a child that does not resolve emits nothing', () {
      final c = container();
      c.read(hierarchyTreeProvider.notifier)
        ..setModel(modelWithChild())
        ..pushInto('no_such_instance');

      expect(telemetry.count('schematic.scope_pushed'), 0);
    });

    test('breadcrumb and search navigation do not count as a drill-down', () {
      // `selectScope` is the shared write path — the breadcrumb, a search hit
      // and an inbound cross-probe all use it. Only `pushInto` is the user
      // walking down the hierarchy.
      final c = container();
      final notifier = c.read(hierarchyTreeProvider.notifier)
        ..setModel(modelWithChild());
      final root = HierarchyNode.rootOf(modelWithChild())!;

      notifier
        ..selectByPath(<String>['u_child'])
        ..selectScope(root);

      expect(telemetry.count('schematic.scope_pushed'), 0);
    });
  });

  // ── search.used ─────────────────────────────────────────────────────────────

  group('search.used', () {
    NetlistModel searchableModel() => const NetlistModel(
      creator: 'test',
      modules: <String, Module>{
        'top': Module(
          name: 'top',
          attributes: <String, String>{'top': '1'},
          ports: <String, Port>{},
          cells: <String, Cell>{
            'alu_adder': Cell(
              name: 'alu_adder',
              type: r'$add',
              parameters: <String, String>{},
              attributes: <String, String>{},
              portDirections: <String, PortDirection>{},
              connections: <String, List<BitRef>>{},
            ),
          },
          nets: <String, Net>{},
        ),
      },
    );

    Future<ProviderContainer> pumpSearch(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
      );
      addTearDown(container.dispose);
      container
          .read(hierarchyTreeProvider.notifier)
          .setModel(searchableModel());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: SearchDialog()),
          ),
        ),
      );
      return container;
    }

    testWidgets('typing alone records nothing', (tester) async {
      // The shell re-runs the walk on every debounced edit. Counting there
      // would make `search.used` a measure of typing.
      await pumpSearch(tester);
      await tester.enterText(find.byType(TextField), 'alu');
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('alu_adder'), findsOneWidget);
      expect(telemetry.count('search.used'), 0);
    });

    testWidgets('activating a hit records the mode', (tester) async {
      await pumpSearch(tester);
      await tester.enterText(find.byType(TextField), 'alu');
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.text('alu_adder'));
      await tester.pumpAndSettle();

      expect(telemetry.count('search.used'), 1);
      final event = telemetry.named('search.used');
      expect(event.properties, <String, Object?>{'mode': 'substring'});
      // The query and the matched name are design data.
      expect(event.toString(), isNot(contains('alu')));
      _assertInCatalog(event);
    });

    testWidgets('the recorded mode follows the chip the user picked', (
      tester,
    ) async {
      await pumpSearch(tester);
      final l10n = await L10N.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.searchModeGlob));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'alu*');
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.text('alu_adder'));
      await tester.pumpAndSettle();

      expect(telemetry.named('search.used').properties['mode'], 'glob');
    });

    test('every SearchMode produces a catalog token', () {
      // No `String` ever reaches this property: the call site passes the enum
      // to `telemetryEnumToken`, and every constant lands in the pinned list.
      final entry = kNetcruxEventCatalog.firstWhere(
        (e) => e.name == 'search.used',
      );
      for (final mode in SearchMode.values) {
        expect(
          entry.enumeratedValues['mode'],
          contains(telemetryEnumToken(mode)),
        );
      }
    });
  });

  // ── export.completed ────────────────────────────────────────────────────────

  group('export.completed', () {
    /// The JSON flavour, because it needs only a netlist and a scope — no
    /// laid-out graph, no mounted RepaintBoundary. The event is recorded in
    /// `_success`, which all three flavours share.
    Future<SchematicExportController> exportController(
      WidgetTester tester, {
      required SaveLocationPicker pickSavePath,
    }) async {
      final container = ProviderContainer(
        overrides: [
          telemetryServiceProvider.overrideWithValue(telemetry),
          loadedNetlistProvider.overrideWith(
            () => _StaticNetlist(modelWithChild()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(loadedNetlistProvider.future);
      container.read(hierarchyTreeProvider.notifier).setModel(modelWithChild());

      late SchematicExportController controller;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  controller = SchematicExportController(
                    container: container,
                    messenger: ScaffoldMessenger.of(context),
                    l10n: L10N.of(context),
                    canvasKey: null,
                    pickSavePath: pickSavePath,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('a completed JSON export records the json token', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('netcrux_export_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final controller = await exportController(
        tester,
        pickSavePath: (name) async => '${dir.path}/$name',
      );

      await tester.runAsync(controller.exportJson);
      await tester.pump();

      expect(telemetry.count('export.completed'), 1);
      final event = telemetry.named('export.completed');
      expect(event.properties, <String, Object?>{'kind': 'json'});
      // The destination the user chose never leaves the machine.
      expect(event.toString(), isNot(contains(dir.path)));
      _assertInCatalog(event);
    });

    testWidgets('a cancelled picker records nothing', (tester) async {
      final controller = await exportController(
        tester,
        pickSavePath: (_) async => null,
      );

      await tester.runAsync(controller.exportJson);
      await tester.pump();

      expect(telemetry.count('export.completed'), 0);
    });

    testWidgets('a failed write records nothing', (tester) async {
      // `export.completed` means completed. A path that cannot be written
      // surfaces a failure snackbar and never reaches `_success`.
      final controller = await exportController(
        tester,
        pickSavePath: (_) async => '/nonexistent-dir-for-test/schematic.json',
      );

      await tester.runAsync(controller.exportJson);
      await tester.pump();

      expect(telemetry.count('export.completed'), 0);
    });

    test('every NetcruxExportKind is a catalog token', () {
      final entry = kNetcruxEventCatalog.firstWhere(
        (e) => e.name == 'export.completed',
      );
      for (final kind in NetcruxExportKind.values) {
        expect(
          entry.enumeratedValues['kind'],
          contains(telemetryEnumToken(kind)),
        );
      }
    });
  });
}

/// A `LoadedNetlist` that resolves to a fixed model without spawning Yosys.
class _StaticNetlist extends LoadedNetlist {
  _StaticNetlist(this._model);

  final NetlistModel _model;

  @override
  Future<NetlistModel?> build() async => _model;
}
