// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/exported_cell_symbol.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/services/schematic_export_controller.dart';
import 'package:netcrux/features/viewer/services/svg_export_palette_from_theme.dart';
import 'package:netcrux/features/viewer/symbols/cell_symbol_svg_source_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

import '../../../helpers/license_status_fixtures.dart';
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
                context: context,
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

    testWidgets('writes the canvas symbols, custom artwork from the '
        'active source, in the theme colours', (tester) async {
      final dir = Directory.systemTemp.createTempSync('nc_export_svg_ok_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final container = ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          currentLaidOutGraphProvider.overrideWith((ref) async => _laidOut()),
          cellSymbolSvgSourceProvider.overrideWithValue(
            (cell) => cell.type == 'alu'
                ? const ExportedCellSymbolSvg(
                    '<svg xmlns="http://www.w3.org/2000/svg" '
                    'viewBox="0 0 10 10"><circle id="alu-art" cx="5" '
                    'cy="5" r="4"/></svg>',
                  )
                : null,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(currentLaidOutGraphProvider.future);

      final controller = await _controller(
        tester,
        reuseContainer: container,
        pickSavePath: (name) async => '${dir.path}/$name',
      );

      await tester.runAsync(controller.exportSvg);
      await tester.pump();

      final file = File('${dir.path}/schematic.svg');
      expect(file.existsSync(), isTrue);
      final svg = file.readAsStringSync();
      expect(svg, contains('<g class="cell" data-kind="andGate"'));
      expect(svg, contains('<svg class="cell custom-symbol" data-type="alu"'));
      // The artwork's ids are made unique to this symbol in the export.
      expect(svg, contains('id="cs0-alu-art"'));
      // The MaterialApp's default (light) theme, not the dark fallback.
      final theme = ThemeData();
      expect(svg, contains(cssHexColor(theme.colorScheme.surface)));
      expect(find.textContaining(file.path), findsOneWidget);
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

  group('the educational-licence mark', () {
    for (final MapEntry(key: name, value: licence) in _licences.entries) {
      final marks = name == 'edu';

      testWidgets('PNG under $name ${marks ? 'carries' : 'has no'} mark', (
        tester,
      ) async {
        final dir = Directory.systemTemp.createTempSync('nc_export_png_edu_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final key = GlobalKey();
        final controller = await _controller(
          tester,
          canvasKey: key,
          keyedChild: RepaintBoundary(
            key: key,
            child: Container(
              width: 300,
              height: 60,
              color: const Color(0xFFFF0000),
            ),
          ),
          pickSavePath: (name) async => '${dir.path}/$name',
          overrides: [licenseStatusProvider.overrideWithValue(licence)],
        );

        await tester.runAsync(controller.exportPng);
        await tester.pump();

        final path = '${dir.path}/schematic.png';
        // Captured at 2x: 600 x 120. The plate sits 12 px in from the
        // bottom-right corner; this pixel is inside it.
        final corner = await tester.runAsync(
          () => _pngPixel(path, 600 - 24, 120 - 16),
        );
        final origin = await tester.runAsync(() => _pngPixel(path, 2, 2));
        expect(origin, <int>[255, 0, 0, 255]);
        if (marks) {
          expect(corner, isNot(<int>[255, 0, 0, 255]));
        } else {
          expect(corner, <int>[255, 0, 0, 255]);
        }
        expect(find.textContaining(path), findsOneWidget);
      });

      testWidgets('SVG under $name ${marks ? 'carries' : 'has no'} mark', (
        tester,
      ) async {
        final dir = Directory.systemTemp.createTempSync('nc_export_svg_edu_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final container = ProviderContainer(
          overrides: [
            ...netcruxTelemetryTestOverrides(),
            currentLaidOutGraphProvider.overrideWith((ref) async => _laidOut()),
            licenseStatusProvider.overrideWithValue(licence),
          ],
        );
        addTearDown(container.dispose);
        await container.read(currentLaidOutGraphProvider.future);
        final controller = await _controller(
          tester,
          reuseContainer: container,
          pickSavePath: (name) async => '${dir.path}/$name',
        );

        await tester.runAsync(controller.exportSvg);
        await tester.pump();

        final svg = File('${dir.path}/schematic.svg').readAsStringSync();
        if (marks) {
          expect(svg, contains('class="edu-mark"'));
          expect(svg, contains('>$_mark</text>'));
        } else {
          expect(svg, isNot(contains('edu-mark')));
          expect(svg, isNot(contains('Non-commercial')));
        }
      });
    }

    testWidgets('the JSON netlist slice is byte-identical under an '
        'educational licence', (tester) async {
      Future<String> exportUnder(CruxLicenseStatus licence) async {
        final dir = Directory.systemTemp.createTempSync('nc_export_json_edu_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final container = ProviderContainer(
          overrides: [
            ...netcruxTelemetryTestOverrides(),
            loadedNetlistProvider.overrideWith(() => _StaticNetlist(_model())),
            licenseStatusProvider.overrideWithValue(licence),
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
        return File('${dir.path}/schematic.json').readAsStringSync();
      }

      final edu = await exportUnder(_licences['edu']!);
      final openCore = await exportUnder(CruxLicenseStatus.openCore);
      expect(edu, isNotEmpty);
      expect(edu, openCore);
      expect(edu, isNot(contains('Non-commercial')));
      expect(edu, isNot(contains('Educational')));
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

/// The three licence states the mark distinguishes: only the first marks.
final Map<String, CruxLicenseStatus> _licences = <String, CruxLicenseStatus>{
  'edu': activeLicenseStatus(LicenseTier.edu),
  'pro': activeLicenseStatus(LicenseTier.pro),
  'open core': CruxLicenseStatus.openCore,
};

const String _mark = 'Made with NetCrux Educational · Non-commercial use only';

/// The RGBA of pixel ([x], [y]) of the PNG at [path].
Future<List<int>> _pngPixel(String path, int x, int y) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final rgba = (await image.toByteData())!;
  final offset = (y * image.width + x) * 4;
  final pixel = [for (var i = 0; i < 4; i++) rgba.getUint8(offset + i)];
  image.dispose();
  codec.dispose();
  return pixel;
}

LaidOutGraph _laidOut() => const LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_and',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[],
      ),
      SchematicCell(
        id: 'u_alu',
        kind: CellKind.generic,
        type: 'alu',
        ports: <SchematicPort>[],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_and',
        bounds: BoundingBox(x: 0, y: 0, width: 60, height: 40),
      ),
      NodePosition(
        id: 'u_alu',
        bounds: BoundingBox(x: 100, y: 0, width: 40, height: 40),
      ),
    ],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 140, height: 40),
  ),
);

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
