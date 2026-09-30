// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/services/schematic_export_controller.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// Pumps a Scaffold, optionally hosting a widget under [canvasKey], and
/// returns a controller wired to that key. [pickSavePath] stands in for
/// the platform save dialog; [overrides] supply the graph / netlist the
/// SVG and JSON flows read.
Future<SchematicExportController> _controller(
  WidgetTester tester, {
  GlobalKey? canvasKey,
  Widget? keyedChild,
  SaveLocationPicker? pickSavePath,
  List<Override> overrides = const [],
  ProviderContainer? reuseContainer,
}) async {
  final container =
      reuseContainer ??
      ProviderContainer(
        overrides: [...netcruxTelemetryTestOverrides(), ...overrides],
      );
  if (reuseContainer == null) addTearDown(container.dispose);
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
                canvasKey: canvasKey,
                pickSavePath: pickSavePath,
              );
              return keyedChild ?? const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  group('SchematicExportController.exportPng — pre-picker guards', () {
    testWidgets('a null canvas key fails with "canvas not mounted"', (
      tester,
    ) async {
      final controller = await _controller(tester);
      final l10n = await L10N.delegate.load(const Locale('en'));
      await controller.exportPng();
      await tester.pump();
      expect(
        find.text(l10n.exportFailureMessage('canvas not mounted')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a key on a non-RepaintBoundary fails accordingly', (
      tester,
    ) async {
      final key = GlobalKey();
      final controller = await _controller(
        tester,
        canvasKey: key,
        keyedChild: Container(key: key),
      );
      final l10n = await L10N.delegate.load(const Locale('en'));
      await controller.exportPng();
      await tester.pump();
      expect(
        find.text(l10n.exportFailureMessage('canvas not a RepaintBoundary')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('cancelling the picker', () {
    for (final flavour in <String>['png', 'svg', 'json']) {
      testWidgets('$flavour writes nothing and reports nothing', (
        tester,
      ) async {
        final key = GlobalKey();
        final controller = await _controller(
          tester,
          canvasKey: key,
          keyedChild: RepaintBoundary(
            key: key,
            child: const SizedBox(width: 8),
          ),
          pickSavePath: (_) async => null,
        );

        await tester.runAsync(() async {
          switch (flavour) {
            case 'png':
              await controller.exportPng();
            case 'svg':
              await controller.exportSvg();
            case 'json':
              await controller.exportJson();
          }
        });
        await tester.pump();

        expect(find.byType(SnackBar), findsNothing);
      });
    }
  });

  group('exportSvg', () {
    testWidgets('no laid-out graph fails with "no graph to export"', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('nc_export_svg_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final controller = await _controller(
        tester,
        pickSavePath: (name) async => '${dir.path}/$name',
      );

      await tester.runAsync(controller.exportSvg);
      await tester.pump();

      expect(find.textContaining('no graph to export'), findsOneWidget);
      expect(File('${dir.path}/schematic.svg').existsSync(), isFalse);
    });
  });

  group('exportJson', () {
    testWidgets('no design loaded fails with "no design loaded"', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('nc_export_json_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final controller = await _controller(
        tester,
        pickSavePath: (name) async => '${dir.path}/$name',
      );

      await tester.runAsync(controller.exportJson);
      await tester.pump();

      expect(find.textContaining('no design loaded'), findsOneWidget);
    });

    testWidgets('writes the active scope slice and reports success', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('nc_export_json_ok_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final container = ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          loadedNetlistProvider.overrideWith(() => _StaticNetlist(_model())),
        ],
      );
      addTearDown(container.dispose);
      await container.read(loadedNetlistProvider.future);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());

      final controller = await _controller(
        tester,
        reuseContainer: container,
        pickSavePath: (name) async => '${dir.path}/$name',
      );

      await tester.runAsync(controller.exportJson);
      await tester.pump();

      final file = File('${dir.path}/schematic.json');
      expect(file.existsSync(), isTrue);
      final slice = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(slice['creator'], 'test');
      expect((slice['modules']! as Map).keys, contains('top'));
      expect(find.textContaining(file.path), findsOneWidget);
    });

    testWidgets('an unwritable destination reports the failure', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          loadedNetlistProvider.overrideWith(() => _StaticNetlist(_model())),
        ],
      );
      addTearDown(container.dispose);
      await container.read(loadedNetlistProvider.future);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());

      final controller = await _controller(
        tester,
        reuseContainer: container,
        pickSavePath: (_) async => '/nonexistent-dir-for-test/schematic.json',
      );

      await tester.runAsync(controller.exportJson);
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('exportPng', () {
    testWidgets('writes a PNG from the repaint boundary', (tester) async {
      final dir = Directory.systemTemp.createTempSync('nc_export_png_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final key = GlobalKey();
      final controller = await _controller(
        tester,
        canvasKey: key,
        keyedChild: RepaintBoundary(
          key: key,
          child: Container(width: 20, height: 20, color: Colors.red),
        ),
        pickSavePath: (name) async => '${dir.path}/$name',
      );

      await tester.runAsync(controller.exportPng);
      await tester.pump();

      final file = File('${dir.path}/schematic.png');
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(0));
      expect(find.textContaining(file.path), findsOneWidget);
    });
  });
}

NetlistModel _model() {
  const top = Module(
    name: 'top',
    attributes: <String, String>{'top': '1'},
    ports: {},
    cells: <String, Cell>{
      'u_cpu': Cell(
        name: 'u_cpu',
        type: 'cpu',
        parameters: {},
        attributes: {},
        portDirections: {},
        connections: {},
      ),
    },
    nets: {},
  );
  const cpu = Module(
    name: 'cpu',
    attributes: <String, String>{},
    ports: {},
    cells: {},
    nets: {},
  );
  return const NetlistModel(
    creator: 'test',
    modules: <String, Module>{'top': top, 'cpu': cpu},
  );
}

class _StaticNetlist extends LoadedNetlist {
  _StaticNetlist(this._model);

  final NetlistModel _model;

  @override
  Future<NetlistModel?> build() async => _model;
}
