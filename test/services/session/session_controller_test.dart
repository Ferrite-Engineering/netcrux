// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/domain/models/session/netcrux_session.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/session_controller.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// The tab's elaboration, answered by [result] instead of Yosys. Watches the
/// project like the real pipeline, so a session's `setProject` rebuilds it.
class _AnsweredNetlist extends LoadedNetlist {
  _AnsweredNetlist(this.result);

  final Future<NetlistModel?> Function() result;

  @override
  Future<NetlistModel?> build() {
    ref.watch(currentProjectProvider);
    return result();
  }
}

/// A tab container whose elaboration resolves through [result] — by default
/// to no design, as when elaboration fails or there are no sources.
ProviderContainer _container({Future<NetlistModel?> Function()? result}) =>
    ProviderContainer(
      overrides: [
        loadedNetlistProvider.overrideWith(
          () => _AnsweredNetlist(result ?? () async => null),
        ),
      ],
    );

/// `top` instantiates `u_cpu` (a `cpu`), which instantiates `u_alu`.
NetlistModel _seed() => const YosysJsonParser().parse(
  File(
    'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
  ).readAsStringSync(),
);

NetcruxSession _session() => const NetcruxSession(
  version: NetcruxSession.currentVersion,
  sourceFilePaths: <String>['/tmp/a.v', '/tmp/b.sv'],
  topModule: 'top',
  scopePath: <String>['u_cpu'],
  zoom: 1.25,
  panX: 12.5,
  panY: -8,
  selectionJson: <String, Object?>{'kind': 'cell', 'cellId': 'u_alu'},
  overlayMode: 'fanin',
  expandedScopeKeys: <String>['', 'u_cpu'],
);

/// Pumps a MaterialApp so the controller has a live [ScaffoldMessengerState]
/// (its error paths snackbar) and captures a [SessionController] bound to
/// [container].
Future<SessionController> _controller(
  WidgetTester tester,
  ProviderContainer container,
) async {
  late SessionController controller;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              controller = SessionController(
                container: container,
                messenger: ScaffoldMessenger.of(context),
                l10n: L10N.of(context),
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

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('netcrux-session-');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String writeFile(String name, String contents) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsStringSync(contents);
    return path;
  }

  group('SessionController.openByPath', () {
    testWidgets('round-trips a saved session back into the providers', (
      tester,
    ) async {
      // Save side (the model already has its own round-trip test) → write
      // the canonical JSON to a temp file, then load it through the
      // controller and assert the state landed.
      final session = _session();
      final path = writeFile(
        'demo.netcrux',
        const JsonEncoder.withIndent('  ').convert(session.toJson()),
      );

      final container = _container();
      addTearDown(container.dispose);
      final controller = await _controller(tester, container);

      await tester.runAsync(() => controller.openByPath(path));
      await tester.pump();

      expect(
        container.read(currentProjectProvider).sourceFiles,
        session.sourceFilePaths,
      );
      final transform = container.read(viewportTransformProvider);
      expect(transform.zoom, session.zoom);
      expect(transform.offset, Offset(session.panX, session.panY));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unknown version surfaces the unknown-version snackbar', (
      tester,
    ) async {
      final path = writeFile(
        'bad.netcrux',
        jsonEncode(<String, Object?>{
          'version': 99,
        }),
      );
      final container = _container();
      addTearDown(container.dispose);
      final controller = await _controller(tester, container);
      final l10n = await L10N.delegate.load(const Locale('en'));

      await tester.runAsync(() => controller.openByPath(path));
      await tester.pump();

      expect(
        find.text(l10n.sessionLoadUnknownVersion(99)),
        findsOneWidget,
      );
      // Nothing was applied.
      expect(container.read(currentProjectProvider).sourceFiles, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('malformed JSON surfaces the load-failed snackbar', (
      tester,
    ) async {
      final path = writeFile('garbage.netcrux', 'this is not json {');
      final container = _container();
      addTearDown(container.dispose);
      final controller = await _controller(tester, container);

      await tester.runAsync(() => controller.openByPath(path));
      await tester.pump();

      // The generic failure envelope is used (exact reason varies).
      expect(find.textContaining('Could not load session'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SessionController.apply — the view waits for the design', () {
    testWidgets(
      'scope, expansion, selection and camera land once elaboration resolves',
      (tester) async {
        final design = Completer<NetlistModel?>();
        final container = _container(result: () => design.future);
        addTearDown(container.dispose);
        final controller = await _controller(tester, container);
        const session = NetcruxSession(
          version: NetcruxSession.currentVersion,
          sourceFilePaths: <String>['/rev/top.v'],
          topModule: 'top',
          scopePath: <String>['u_cpu'],
          zoom: 1.25,
          panX: 12.5,
          panY: -8,
          selectionJson: <String, Object?>{
            'kind': 'cell',
            'cellId': 'u_alu',
          },
          overlayMode: null,
          expandedScopeKeys: <String>['', 'u_cpu', 'u_cpu/u_alu'],
        );

        final applied = controller.apply(session);
        await tester.pump();
        // Elaboration is still running: nothing that needs the design moved.
        expect(container.read(hierarchyTreeProvider).model, isNull);

        final model = _seed();
        design.complete(model);
        await tester.runAsync(() => applied);

        final tree = container.read(hierarchyTreeProvider);
        expect(tree.model, same(model));
        expect(tree.selected?.path, <String>['u_cpu']);
        expect(tree.expandedKeys, containsAll(<String>['u_cpu/u_alu']));
        expect(
          container.read(selectedElementProvider).primary,
          const SelectedElement.cell(cellId: 'u_alu'),
        );
        // The camera waits for the u_cpu layout instead of being fitted away.
        expect(
          container.read(viewportTransformProvider.notifier).takePendingRestore(
            const <String>['u_cpu'],
          ),
          const ViewportTransform(zoom: 1.25, offset: Offset(12.5, -8)),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('restoring into a tab showing a different design replaces its '
        'view', (tester) async {
      final other = _seed();
      var answer = other;
      final container = _container(result: () async => answer);
      addTearDown(container.dispose);
      // The tab shows another design, navigated somewhere of its own.
      container.read(currentProjectProvider.notifier).setSourceFiles(
        const <String>['/other/top.v'],
      );
      await tester.runAsync(() => container.read(loadedNetlistProvider.future));
      container.read(hierarchyTreeProvider.notifier)
        ..setModel(other)
        ..selectByPath(const <String>['u_cpu', 'u_alu']);

      final controller = await _controller(tester, container);
      answer = _seed();
      const session = NetcruxSession(
        version: NetcruxSession.currentVersion,
        sourceFilePaths: <String>['/rev/top.v'],
        topModule: 'top',
        scopePath: <String>['u_cpu'],
        zoom: 2,
        panX: 0,
        panY: 0,
        selectionJson: null,
        overlayMode: null,
        expandedScopeKeys: <String>['', 'u_cpu'],
      );
      await tester.runAsync(() => controller.apply(session));

      final tree = container.read(hierarchyTreeProvider);
      expect(tree.model, same(answer));
      expect(tree.selected?.path, <String>['u_cpu']);
      expect(container.read(currentProjectProvider).sourceFiles, <String>[
        '/rev/top.v',
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a saved scope the design no longer has leaves the fit alone', (
      tester,
    ) async {
      final container = _container(result: () async => _seed());
      addTearDown(container.dispose);
      final controller = await _controller(tester, container);
      await tester.runAsync(
        () => controller.apply(
          const NetcruxSession(
            version: NetcruxSession.currentVersion,
            sourceFilePaths: <String>['/rev/top.v'],
            topModule: 'top',
            scopePath: <String>['u_gone'],
            zoom: 2,
            panX: 0,
            panY: 0,
            selectionJson: null,
            overlayMode: null,
            expandedScopeKeys: <String>[],
          ),
        ),
      );
      expect(container.read(hierarchyTreeProvider).selected?.path, isEmpty);
      final viewport = container.read(viewportTransformProvider.notifier);
      expect(viewport.takePendingRestore(const <String>[]), isNull);
      expect(viewport.takePendingRestore(const <String>['u_gone']), isNull);
    });
  });

  group('SessionController.saveToPath', () {
    /// Saves the container's live viewer state and reads the emitted
    /// session back off disk.
    Future<Map<String, Object?>> saveAndRead(
      WidgetTester tester,
      ProviderContainer container,
      String name,
    ) async {
      final controller = await _controller(tester, container);
      final path = '${tempDir.path}/$name';
      await tester.runAsync(() => controller.saveToPath(path));
      await tester.pump();
      return jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    }

    testWidgets('an empty selection persists a null selection record', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);

      final json = await saveAndRead(tester, container, 'empty.netcrux');

      expect(json.containsKey('selection'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the emitted session reports the save path in a snackbar', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      final controller = await _controller(tester, container);
      final path = '${tempDir.path}/ok.netcrux';

      await tester.runAsync(() => controller.saveToPath(path));
      await tester.pump();

      expect(find.textContaining(path), findsOneWidget);
    });

    testWidgets('an unwritable path surfaces the failure snackbar', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      final controller = await _controller(tester, container);

      await tester.runAsync(
        () => controller.saveToPath('${tempDir.path}/missing-dir/s.netcrux'),
      );
      await tester.pump();

      expect(find.textContaining('Could not load session'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (label, element) in <(String, SelectedElement)>[
      ('cell', const SelectedElement.cell(cellId: 'u_alu')),
      (
        'port',
        const SelectedElement.port(
          cellId: 'u_alu',
          portId: 'u_alu:clk',
          portName: 'clk',
        ),
      ),
      (
        'boundaryPort',
        const SelectedElement.boundaryPort(
          portId: 'top:rst_n',
          portName: 'rst_n',
        ),
      ),
      ('wire', const SelectedElement.wire(edgeId: 'e_7_0', netId: 7)),
    ]) {
      testWidgets('a $label selection round-trips through the file', (
        tester,
      ) async {
        final saver = _container();
        addTearDown(saver.dispose);
        saver.read(selectedElementProvider.notifier).select(element);

        final controller = await _controller(tester, saver);
        final path = '${tempDir.path}/$label.netcrux';
        await tester.runAsync(() => controller.saveToPath(path));
        await tester.pump();

        final loader = _container();
        addTearDown(loader.dispose);
        final reader = await _controller(tester, loader);
        await tester.runAsync(() => reader.openByPath(path));
        await tester.pump();

        expect(loader.read(selectedElementProvider).primary, element);
      });
    }

    testWidgets('a multi-selection round-trips primary and extras', (
      tester,
    ) async {
      const first = SelectedElement.cell(cellId: 'u_alu');
      const second = SelectedElement.cell(cellId: 'u_dma');
      final saver = _container();
      addTearDown(saver.dispose);
      saver.read(selectedElementProvider.notifier)
        ..select(first)
        ..addToSelection(second);

      final controller = await _controller(tester, saver);
      final path = '${tempDir.path}/multi.netcrux';
      await tester.runAsync(() => controller.saveToPath(path));
      await tester.pump();

      final loader = _container();
      addTearDown(loader.dispose);
      final reader = await _controller(tester, loader);
      await tester.runAsync(() => reader.openByPath(path));
      await tester.pump();

      final restored = loader.read(selectedElementProvider);
      expect(restored.primary, second);
      expect(restored.elements, containsAll(<SelectedElement>[first, second]));
    });
  });

  group('selection decoding tolerance', () {
    Future<Selection> load(WidgetTester tester, Object? selectionJson) async {
      final path = '${tempDir.path}/tolerant.netcrux';
      File(path).writeAsStringSync(
        jsonEncode(<String, Object?>{
          ..._session().toJson(),
          'selection': selectionJson,
        }),
      );
      final container = _container();
      addTearDown(container.dispose);
      final controller = await _controller(tester, container);
      await tester.runAsync(() => controller.openByPath(path));
      await tester.pump();
      return await container.read(selectedElementProvider);
    }

    testWidgets('an unknown element kind decodes to an empty selection', (
      tester,
    ) async {
      final selection = await load(tester, <String, Object?>{
        'kind': 'sasquatch',
      });
      expect(selection.isEmpty, isTrue);
    });

    testWidgets('a cell record missing its id decodes to empty', (
      tester,
    ) async {
      final selection = await load(tester, <String, Object?>{'kind': 'cell'});
      expect(selection.isEmpty, isTrue);
    });

    testWidgets('a port record missing a field decodes to empty', (
      tester,
    ) async {
      final selection = await load(tester, <String, Object?>{
        'kind': 'port',
        'cellId': 'u_alu',
      });
      expect(selection.isEmpty, isTrue);
    });

    testWidgets('a wire record missing its net id decodes to empty', (
      tester,
    ) async {
      final selection = await load(tester, <String, Object?>{
        'kind': 'wire',
        'edgeId': 'e_1_0',
      });
      expect(selection.isEmpty, isTrue);
    });

    testWidgets('non-map entries in the extras list are skipped', (
      tester,
    ) async {
      final selection = await load(tester, <String, Object?>{
        'kind': 'cell',
        'cellId': 'u_alu',
        'elements': <Object?>[
          'not a map',
          <String, Object?>{'kind': 'cell', 'cellId': 'u_dma'},
        ],
      });
      expect(selection.elements, hasLength(2));
      expect(selection.primary, const SelectedElement.cell(cellId: 'u_alu'));
    });
  });
}
