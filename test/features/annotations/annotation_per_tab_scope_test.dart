// Each tab's annotations belong to that tab's design (netcrux#17).
// `annotationStateProvider` was one app-wide keepAlive notifier
// registered at root only, so an annotation made on
// `fsm_lock`'s `$procdff$17` showed in the SoC tab's panel and was saved
// into the SoC tab's session.
//
// Uses the production container topology: a root container and per-tab
// children built from `netcruxTabOverridesFactory`, as `bootstrap` composes
// them.
import 'dart:convert';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/session/netcrux_session.dart';
import 'package:netcrux/features/annotations/providers/annotation_reveal_request.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/schematic/schematic_annotation_markers_provider.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';
import 'package:netcrux/services/session/session_controller.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

import '../../helpers/telemetry_test_overrides.dart';

const Annotation _fsmNote = Annotation(
  id: 'an-0',
  title: 'State register',
  body: 'Check the reset value',
  targetKind: AnnotationTargetKind.cell,
  targetId: r'$procdff$17',
  createdAtMillis: 1,
  updatedAtMillis: 1,
  moduleName: 'fsm_lock',
);

Annotation _annotation(String id, String targetId, {String? moduleName}) =>
    Annotation(
      id: id,
      targetKind: AnnotationTargetKind.cell,
      targetId: targetId,
      body: 'b',
      createdAtMillis: 1,
      updatedAtMillis: 1,
      moduleName: moduleName,
    );

/// `top` instantiates `u_cpu` (module `cpu`, cells `u_alu` and `pc_reg`).
NetlistModel _seed() => const YosysJsonParser().parse(
  File(
    'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
  ).readAsStringSync(),
);

/// The tab's elaboration resolves to no design, so applying a session
/// restores its annotations without running Yosys.
class _NoDesign extends LoadedNetlist {
  @override
  Future<NetlistModel?> build() async => null;
}

void main() {
  late ProviderContainer root;
  late TabContainerManager manager;

  setUp(() {
    root = ProviderContainer(
      overrides: <Override>[...netcruxTelemetryTestOverrides()],
    );
    manager = TabContainerManager(
      rootContainer: root,
      overridesFactory: netcruxTabOverridesFactory,
    );
  });

  tearDown(() {
    manager.dispose();
    root.dispose();
  });

  group('annotations are per tab', () {
    test(
      'a titled annotation added in tab A is absent from tab B and root',
      () {
        final tabA = manager.containerFor(TabId.generate());
        final tabB = manager.containerFor(TabId.generate());

        tabA.read(annotationStoreProvider).addAnnotation(_fsmNote);

        expect(
          tabA.read(annotationSnapshotProvider).annotations,
          <Annotation>[_fsmNote],
        );
        expect(
          tabB.read(annotationSnapshotProvider).annotations,
          isEmpty,
          reason: "a sibling tab's panel must not list tab A's annotation",
        );
        expect(
          tabB.read(annotationStoreProvider).snapshot().isEmpty,
          isTrue,
        );
        expect(root.read(annotationSnapshotProvider).isEmpty, isTrue);
      },
    );

    test('an annotation added in tab A is absent from tab B', () {
      final tabA = manager.containerFor(TabId.generate());
      final tabB = manager.containerFor(TabId.generate());

      tabA
          .read(annotationStoreProvider)
          .addAnnotation(_annotation('an-1', 'u_cpu'));

      expect(
        tabA.read(annotationSnapshotProvider).annotations,
        hasLength(1),
      );
      expect(
        tabB.read(annotationSnapshotProvider).annotations,
        isEmpty,
      );
    });

    test("a cell's badge marks its own tab's canvas only", () {
      final tabA = manager.containerFor(TabId.generate());
      final tabB = manager.containerFor(TabId.generate());
      tabA.read(hierarchyTreeProvider.notifier).setModel(_seed());
      tabB.read(hierarchyTreeProvider.notifier).setModel(_seed());

      tabA
          .read(annotationStoreProvider)
          .addAnnotation(_annotation('an-1', 'u_cpu', moduleName: 'top'));

      expect(
        tabA.read(schematicAnnotationMarkersProvider)?.cells.keys,
        <String>['u_cpu'],
      );
      expect(tabB.read(schematicAnnotationMarkersProvider), isNull);
      expect(root.read(schematicAnnotationMarkersProvider), isNull);
    });

    test('the reveal request is per tab', () {
      final tabA = manager.containerFor(TabId.generate());
      final tabB = manager.containerFor(TabId.generate());
      tabA.read(annotationRevealRequestProvider.notifier).request('an-1');
      expect(tabA.read(annotationRevealRequestProvider), 'an-1');
      expect(tabB.read(annotationRevealRequestProvider), isNull);
    });
  });

  group('badges follow the module the note was written in', () {
    test('a note on cpu.pc_reg badges only scopes of module cpu', () {
      final tab = manager.containerFor(TabId.generate());
      tab.read(hierarchyTreeProvider.notifier).setModel(_seed());
      tab
          .read(annotationStoreProvider)
          .addAnnotation(_annotation('an-1', 'pc_reg', moduleName: 'cpu'));

      expect(tab.read(hierarchyTreeProvider).selected?.moduleName, 'top');
      expect(tab.read(schematicAnnotationMarkersProvider), isNull);

      tab.read(hierarchyTreeProvider.notifier).selectByPath(<String>['u_cpu']);
      expect(tab.read(hierarchyTreeProvider).selected?.moduleName, 'cpu');
      expect(
        tab.read(schematicAnnotationMarkersProvider)?.cells.keys,
        <String>['pc_reg'],
      );
    });

    test('a note saved without a module badges its id in any scope', () {
      final tab = manager.containerFor(TabId.generate());
      tab.read(hierarchyTreeProvider.notifier).setModel(_seed());
      tab
          .read(annotationStoreProvider)
          .addAnnotation(_annotation('an-1', 'u_cpu'));
      expect(
        tab.read(schematicAnnotationMarkersProvider)?.cells.keys,
        <String>['u_cpu'],
      );
    });
  });

  group('session save and restore keep each tab its own', () {
    late Directory tempDir;
    setUp(
      () => tempDir = Directory.systemTemp.createTempSync('netcrux_notes_'),
    );
    tearDown(() => tempDir.deleteSync(recursive: true));

    Future<SessionController> controllerFor(
      WidgetTester tester,
      ProviderContainer tab,
    ) async {
      late SessionController controller;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: tab,
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  controller = SessionController(
                    container: tab,
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
      return controller;
    }

    ProviderContainer newTab() {
      final tab = manager.containerFor(TabId.generate());
      // A per-tab override can only be layered on by a child container, so
      // the elaboration stand-in sits under the tab's own container.
      final child = ProviderContainer(
        parent: tab,
        overrides: <Override>[
          loadedNetlistProvider.overrideWith(_NoDesign.new),
        ],
      );
      addTearDown(child.dispose);
      return child;
    }

    testWidgets('tab A saves its annotations, tab B saves none, and a restored '
        'tab gets only A', (tester) async {
      final tabA = newTab();
      final tabB = newTab();
      tabA.read(annotationStoreProvider)
        ..addAnnotation(_fsmNote)
        ..addAnnotation(
          _annotation('an-1', r'$procdff$17', moduleName: 'fsm_lock'),
        );

      final pathA = '${tempDir.path}/a.netcrux';
      final pathB = '${tempDir.path}/b.netcrux';
      final controllerForA = await controllerFor(tester, tabA);
      final savedA = await tester.runAsync(
        () => controllerForA.saveToPath(pathA),
      );
      final controllerForB = await controllerFor(tester, tabB);
      final savedB = await tester.runAsync(
        () => controllerForB.saveToPath(pathB),
      );
      expect(savedA, isTrue);
      expect(savedB, isTrue);

      final jsonA =
          jsonDecode(File(pathA).readAsStringSync()) as Map<String, Object?>;
      final jsonB =
          jsonDecode(File(pathB).readAsStringSync()) as Map<String, Object?>;
      expect(jsonA['version'], NetcruxSession.currentVersion);
      expect(jsonA.containsKey('bookmarks'), isFalse);
      expect(NetcruxSession.fromJson(jsonA).annotations.first, _fsmNote);
      expect(NetcruxSession.fromJson(jsonA).annotations, hasLength(2));
      expect(jsonB.containsKey('bookmarks'), isFalse);
      expect(jsonB.containsKey('annotations'), isFalse);

      // Restore A's session into a fresh tab C: C has A's entries, B still
      // has none.
      final tabC = newTab();
      final controllerC = await controllerFor(tester, tabC);
      await tester.runAsync(() => controllerC.openByPath(pathA));
      await tester.pump();
      expect(
        tabC.read(annotationSnapshotProvider).annotations.first,
        _fsmNote,
      );
      expect(
        tabC.read(annotationSnapshotProvider).annotations,
        hasLength(2),
      );
      expect(tabB.read(annotationSnapshotProvider).isEmpty, isTrue);
      expect(
        tabA.read(annotationSnapshotProvider).annotations,
        hasLength(2),
      );

      // Restoring B's empty session into A clears A, and only A.
      final controllerA = await controllerFor(tester, tabA);
      await tester.runAsync(() => controllerA.openByPath(pathB));
      await tester.pump();
      expect(tabA.read(annotationSnapshotProvider).isEmpty, isTrue);
      expect(
        tabC.read(annotationSnapshotProvider).annotations,
        hasLength(2),
      );
    });

    testWidgets('an older session whose bookmark carries a colour restores it '
        'as an annotation', (
      tester,
    ) async {
      final path = '${tempDir.path}/old.netcrux';
      File(path).writeAsStringSync(r'''
{
  "version": 1,
  "sourceFiles": [],
  "topModule": "",
  "scopePath": [],
  "zoom": 1.0,
  "panX": 0.0,
  "panY": 0.0,
  "expandedScopes": [],
  "bookmarks": [
    {
      "id": "bm-1",
      "name": "State register",
      "targetKind": "cell",
      "targetId": "$procdff$17",
      "createdAtMillis": 1,
      "colorHex": "#FF8800",
      "note": "Check the reset value"
    }
  ]
}
''');
      final tab = newTab();
      final controller = await controllerFor(tester, tab);
      await tester.runAsync(() => controller.openByPath(path));
      await tester.pump();
      final restored = tab.read(annotationSnapshotProvider).annotations;
      expect(restored.single.title, 'State register');
      expect(restored.single.body, 'Check the reset value');
      expect(restored.single.toJson().keys, isNot(contains('colorHex')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the legacy fixture opens as annotations and saves without '
        'bookmarks', (tester) async {
      final tab = newTab();
      final controller = await controllerFor(tester, tab);
      await tester.runAsync(
        () => controller.openByPath(
          'test/fixtures/session/legacy_bookmarks_v1.netcrux',
        ),
      );
      await tester.pump();
      final restored = tab.read(annotationSnapshotProvider).annotations;
      expect(restored.map((a) => a.title), <String?>[
        'State register',
        'Unlock input',
        null,
      ]);
      expect(restored.first.body, 'Check the reset value');

      final out = '${tempDir.path}/resaved.netcrux';
      final saved = await tester.runAsync(() => controller.saveToPath(out));
      expect(saved, isTrue);
      final json =
          jsonDecode(File(out).readAsStringSync()) as Map<String, Object?>;
      expect(json['version'], NetcruxSession.currentVersion);
      expect(json.containsKey('bookmarks'), isFalse);
      final annotations = json['annotations']! as List<Object?>;
      expect(annotations, hasLength(3));
      expect(
        (annotations.first! as Map<String, Object?>)['title'],
        'State register',
      );
    });
  });
}
