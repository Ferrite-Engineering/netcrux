// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_annotations/crux_annotations.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/annotation_callouts/annotation_callouts_toggle.dart';
import 'package:netcrux/features/annotation_callouts/schematic_callout_layer.dart';
import 'package:netcrux/features/annotations/providers/annotation_statuses_provider.dart';
import 'package:netcrux/features/annotations/services/annotation_openers.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart'
    show ViewportTransform;
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/annotation_state.dart';

/// Two cells, u_alu at design (60, 120) and u_reg at (240, 120), each
/// 80 × 60, on a 400 × 300 layout.
LaidOutGraph _graph() {
  const graph = SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_alu',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[],
      ),
      SchematicCell(
        id: 'u_reg',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  );
  const layout = NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_alu',
        bounds: BoundingBox(x: 60, y: 120, width: 80, height: 60),
      ),
      NodePosition(
        id: 'u_reg',
        bounds: BoundingBox(x: 240, y: 120, width: 80, height: 60),
      ),
    ],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 400, height: 300),
  );
  return const LaidOutGraph(graph: graph, layout: layout);
}

Annotation _note(
  String id,
  String targetId, {
  AnnotationTargetKind kind = AnnotationTargetKind.cell,
  bool collapsed = false,
  String? authorId,
  bool hidden = false,
}) => Annotation(
  id: id,
  targetKind: kind,
  targetId: targetId,
  title: 'Note $id',
  body: 'Rises one cycle late',
  createdAtMillis: 1,
  updatedAtMillis: 1,
  moduleName: 'top',
  authorId: authorId,
  hidden: hidden,
  placement: CruxCalloutPlacement(collapsed: collapsed),
);

typedef _Harness = ({
  ProviderContainer container,
  List<AnnotationTarget> shown,
});

Future<_Harness> _pump(
  WidgetTester tester, {
  required List<Annotation> notes,
  required Map<String, CruxAnnotationStatus> statuses,
  LicenseTier tier = LicenseTier.openCore,
  bool beta = false,
  double zoom = 1,
  List<Override> extra = const <Override>[],
}) async {
  final shown = <AnnotationTarget>[];
  final container = ProviderContainer(
    overrides: <Override>[
      currentLaidOutGraphProvider.overrideWith((ref) async => _graph()),
      annotationStatusesProvider.overrideWithValue(statuses),
      licenseTierProvider.overrideWithValue(tier),
      betaPeriodProvider.overrideWithValue(beta),
      showAnnotationForTargetOpenerProvider.overrideWithValue(
        (_, _, target) => shown.add(target),
      ),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  container.read(annotationStateProvider.notifier).setAnnotations(notes);
  container
      .read(viewportTransformProvider.notifier)
      .restore(ViewportTransform(zoom: zoom, offset: Offset.zero));
  await container.read(currentLaidOutGraphProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object?>>[
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: Stack(children: <Widget>[SchematicCalloutLayer()]),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, shown: shown);
}

Finder _callout(String id) =>
    find.byKey(ValueKey<String>('annotationCallout-$id'));

Annotation _stored(ProviderContainer c, String id) =>
    c.read(annotationStateProvider).annotations.firstWhere((n) => n.id == id);

void main() {
  group('tier', () {
    final notes = <Annotation>[_note('a', 'u_alu')];
    const statuses = <String, CruxAnnotationStatus>{
      'a': CruxAnnotationStatus.resolved,
    };

    for (final tier in LicenseTier.values) {
      for (final beta in <bool>[false, true]) {
        testWidgets(
          'available at ${tier.name}${beta ? ' during the beta' : ''}',
          (tester) async {
            await _pump(
              tester,
              notes: notes,
              statuses: statuses,
              tier: tier,
              beta: beta,
            );
            expect(_callout('a'), findsOneWidget);
            expect(find.byType(CruxCalloutBalloon), findsOneWidget);
          },
        );
      }
    }

    testWidgets('the View toggle hides and shows them', (tester) async {
      final h = await _pump(tester, notes: notes, statuses: statuses);
      h.container.read(annotationCalloutsVisibleProvider.notifier).toggle();
      await tester.pumpAndSettle();
      expect(_callout('a'), findsNothing);
      h.container.read(annotationCalloutsVisibleProvider.notifier).toggle();
      await tester.pumpAndSettle();
      expect(_callout('a'), findsOneWidget);
    });
  });

  group('what is drawn', () {
    testWidgets('only notes on elements of the scope on screen', (
      tester,
    ) async {
      await _pump(
        tester,
        notes: <Annotation>[
          _note('here', 'u_alu'),
          _note('drift', 'u_reg'),
          _note('away', 'u_other'),
          _note('gone', 'u_gone'),
          _note('scope', 'top.u_sub', kind: AnnotationTargetKind.scope),
          _note('hidden', 'u_alu', hidden: true),
        ],
        statuses: const <String, CruxAnnotationStatus>{
          'here': CruxAnnotationStatus.resolved,
          'drift': CruxAnnotationStatus.drifted,
          'away': CruxAnnotationStatus.orphaned,
          'gone': CruxAnnotationStatus.unresolved,
          'scope': CruxAnnotationStatus.unanchoredToRow,
          'hidden': CruxAnnotationStatus.resolved,
        },
      );
      expect(_callout('here'), findsOneWidget);
      expect(_callout('drift'), findsOneWidget);
      for (final id in <String>['away', 'gone', 'scope', 'hidden']) {
        expect(_callout(id), findsNothing, reason: id);
      }
    });

    testWidgets('a drifted note is dashed, amber and italic', (tester) async {
      await _pump(
        tester,
        notes: <Annotation>[_note('drift', 'u_reg')],
        statuses: const <String, CruxAnnotationStatus>{
          'drift': CruxAnnotationStatus.drifted,
        },
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<CruxCalloutLeadersPainter>()
          .single;
      expect(painter.leaders.single.dashed, isTrue);
      expect(painter.leaders.single.color, kCruxAnnotationDriftedColor);
      final balloon = tester.widget<CruxCalloutBalloon>(
        find.byType(CruxCalloutBalloon),
      );
      expect(balloon.drifted, isTrue);
    });

    testWidgets('the label sits above the element and the leader reaches it', (
      tester,
    ) async {
      await _pump(
        tester,
        notes: <Annotation>[_note('a', 'u_alu')],
        statuses: const <String, CruxAnnotationStatus>{
          'a': CruxAnnotationStatus.resolved,
        },
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<CruxCalloutLeadersPainter>()
          .single;
      // u_alu's top edge is y 120; its middle x 100. Zoom 1, no pan.
      expect(painter.leaders.single.from, const Offset(100, 120));
      final origin = tester.getTopLeft(_callout('a'));
      final layerOrigin = tester.getTopLeft(find.byType(SchematicCalloutLayer));
      expect(origin - layerOrigin, const Offset(100, 120 - 32));
    });
  });

  group('level of detail', () {
    final notes = <Annotation>[_note('a', 'u_alu')];
    const statuses = <String, CruxAnnotationStatus>{
      'a': CruxAnnotationStatus.resolved,
    };

    testWidgets('a balloon at detail zoom', (tester) async {
      await _pump(tester, notes: notes, statuses: statuses);
      expect(find.byType(CruxCalloutBalloon), findsOneWidget);
    });

    testWidgets('a numbered dot at middle zoom, and a tap opens the panel', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        notes: notes,
        statuses: statuses,
        zoom: 0.5,
      );
      expect(find.byType(CruxCalloutBalloon), findsNothing);
      expect(find.byType(CruxCalloutNumberDot), findsOneWidget);
      expect(tester.getSize(_callout('a')), const Size.square(24));
      await tester.tap(find.byType(CruxCalloutNumberDot));
      await tester.pump();
      expect(h.shown, <AnnotationTarget>[
        const AnnotationTarget(
          kind: AnnotationTargetKind.cell,
          targetId: 'u_alu',
        ),
      ]);
    });

    testWidgets('nothing in the overview', (tester) async {
      await _pump(tester, notes: notes, statuses: statuses, zoom: 0.1);
      expect(_callout('a'), findsNothing);
    });
  });

  group('drag and fold', () {
    testWidgets('dragging moves the label and never the element', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        notes: <Annotation>[_note('a', 'u_alu')],
        statuses: const <String, CruxAnnotationStatus>{
          'a': CruxAnnotationStatus.resolved,
        },
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CruxCalloutBalloon)),
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump();
      // Nothing is written until the drag ends.
      expect(_stored(h.container, 'a').placement.labelDx, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      final stored = _stored(h.container, 'a');
      expect(stored.targetId, 'u_alu');
      expect(stored.placement.labelDx, greaterThan(0));
      expect(stored.placement.labelDy, greaterThan(-32));
    });

    testWidgets('the fold control folds, and a tap on the dot unfolds', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        notes: <Annotation>[_note('a', 'u_alu')],
        statuses: const <String, CruxAnnotationStatus>{
          'a': CruxAnnotationStatus.resolved,
        },
      );
      expect(
        tester.getSize(
          find
              .ancestor(
                of: find.byIcon(Icons.unfold_less),
                matching: find.byType(SizedBox),
              )
              .first,
        ),
        const Size.square(24),
      );
      await tester.tap(find.byIcon(Icons.unfold_less));
      await tester.pumpAndSettle();
      expect(_stored(h.container, 'a').placement.collapsed, isTrue);
      expect(find.byType(CruxCalloutNumberDot), findsOneWidget);
      await tester.tap(find.byType(CruxCalloutNumberDot));
      await tester.pumpAndSettle();
      expect(_stored(h.container, 'a').placement.collapsed, isFalse);
    });

    testWidgets("somebody else's note neither moves nor folds", (tester) async {
      final h = await _pump(
        tester,
        notes: <Annotation>[_note('a', 'u_alu', authorId: 'peer-2')],
        statuses: const <String, CruxAnnotationStatus>{
          'a': CruxAnnotationStatus.resolved,
        },
      );
      expect(find.byIcon(Icons.unfold_less), findsNothing);
      await tester.drag(find.byType(CruxCalloutBalloon), const Offset(40, 20));
      await tester.pumpAndSettle();
      expect(_stored(h.container, 'a').placement, const CruxCalloutPlacement());
    });

    testWidgets('past six balloons the rest are dots', (tester) async {
      final notes = <Annotation>[
        for (var i = 0; i < 8; i++) _note('n$i', i.isEven ? 'u_alu' : 'u_reg'),
      ];
      await _pump(
        tester,
        notes: notes,
        statuses: <String, CruxAnnotationStatus>{
          for (final n in notes) n.id: CruxAnnotationStatus.resolved,
        },
      );
      expect(find.byType(CruxCalloutBalloon), findsNWidgets(6));
      expect(find.byType(CruxCalloutNumberDot), findsNWidgets(6 + 2));
    });
  });

  group('keyboard and screen reader', () {
    testWidgets('Tab reaches each callout; Enter opens it, Space folds it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = await _pump(
        tester,
        notes: <Annotation>[_note('a', 'u_alu'), _note('b', 'u_reg')],
        statuses: const <String, CruxAnnotationStatus>{
          'a': CruxAnnotationStatus.resolved,
          'b': CruxAnnotationStatus.drifted,
        },
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expectFocusAnnounced(tester, named: 'Annotation 1: Note a');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(h.shown.single.targetId, 'u_alu');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(_stored(h.container, 'a').placement.collapsed, isTrue);
      semantics.dispose();
    });

    testWidgets(
      'the focus walk: one named stop per callout, in reading order',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(
          tester,
          notes: <Annotation>[_note('a', 'u_alu'), _note('b', 'u_reg')],
          statuses: const <String, CruxAnnotationStatus>{
            'a': CruxAnnotationStatus.resolved,
            'b': CruxAnnotationStatus.drifted,
          },
        );
        final walk = await walkFocus(tester);
        expectCleanFocusWalk(walk);
        expectFocusWalkGolden(
          walk,
          'test/features/annotation_callouts/goldens/'
          'annotation_callouts_focus_walk.txt',
        );
        semantics.dispose();
      },
    );

    testWidgets('a drifted callout says so', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        notes: <Annotation>[_note('b', 'u_reg')],
        statuses: const <String, CruxAnnotationStatus>{
          'b': CruxAnnotationStatus.drifted,
        },
      );
      expect(
        find.bySemanticsLabel(RegExp('Annotation 1: Note b.*Drifted')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });
}
