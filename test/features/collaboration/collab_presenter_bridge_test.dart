// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/schematic_collaboration_service.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/collaboration/collab_follow_detached_provider.dart';
import 'package:netcrux/features/collaboration/collab_presence_publisher.dart';
import 'package:netcrux/features/collaboration/collab_presenter_bridge.dart';
import 'package:netcrux/features/collaboration/collab_view_degradation_provider.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';

/// Records what the bridge publishes; the session stream is driven by the test.
class _RecordingService implements SchematicCollaborationService {
  final controller = StreamController<SchematicCollabSessionState?>.broadcast();
  final published = <SchematicCollabPresenterView>[];
  final announcedScopes = <String>[];

  @override
  Stream<SchematicCollabSessionState?> get sessionState => controller.stream;

  @override
  bool get isInSession => true;

  @override
  void updatePresenterView(SchematicCollabPresenterView view) =>
      published.add(view);

  @override
  void announceScope({required String scopePath, String? netlistContentHash}) =>
      announcedScopes.add(scopePath);

  @override
  void updateSelection({
    required String scopePath,
    required Set<String> elementIds,
  }) {}

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `top` instantiates `u_cpu`, a `cpu`, so there are two scopes to move
/// between.
const _model = NetlistModel(
  creator: 'test',
  modules: {
    'top': Module(
      name: 'top',
      attributes: {'top': '00000000000000000000000000000001'},
      ports: {},
      cells: {
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
    ),
    'cpu': Module(name: 'cpu', attributes: {}, ports: {}, cells: {}, nets: {}),
  },
);

const _participants = [
  SchematicParticipantInfo(
    id: 'ada',
    displayName: 'Ada',
    colorIndex: 0,
    isHost: true,
  ),
  SchematicParticipantInfo(
    id: 'grace',
    displayName: 'Grace',
    colorIndex: 1,
    isHost: false,
  ),
];

SchematicCollabSessionState _session({
  required String me,
  String? presenterId,
  SchematicCollabPresenterView? view,
}) => SchematicCollabSessionState(
  sessionId: 'ABC123',
  myParticipantId: me,
  hostId: 'ada',
  mode: SchematicCollabMode.lan,
  participants: _participants,
  presenterId: presenterId,
  presenterView: view,
);

/// The dock without the reveal: opening a panel here lists it and nothing
/// else, so these tests need no persisted layout.
class _BareDock extends AnalysisDockNotifier {
  @override
  void open(AnalysisPanelKind kind) {
    if (!state.contains(kind)) state = [...state, kind];
  }
}

void main() {
  late _RecordingService service;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    bool pro = true,
  }) async {
    service = _RecordingService();
    container = ProviderContainer(
      overrides: [
        analysisDockProvider.overrideWith(_BareDock.new),
        collabProPanelsAvailableProvider.overrideWithValue(pro),
        schematicCollaborationServiceProvider.overrideWithValue(service),
        // Idle resume has its own tests; here it would only leave a timer.
        collabFollowIdleResumeProvider.overrideWithValue(null),
      ],
    );
    // Closed after the container: the container's stream subscription is what
    // a broadcast controller's close waits on.
    addTearDown(() => unawaited(service.controller.close()));
    addTearDown(container.dispose);
    container.read(hierarchyTreeProvider.notifier).setModel(_model);
    // A laid-out canvas of known size, so a camera can be placed on it.
    container
        .read(viewportTransformProvider.notifier)
        .fitToBounds(
          const Size(800, 600),
          const BoundingBox(x: 0, y: 0, width: 400, height: 300),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CollabPresenterBridge(child: SizedBox.shrink()),
      ),
    );
  }

  Future<void> emit(WidgetTester tester, SchematicCollabSessionState? s) async {
    service.controller.add(s);
    await tester.pump();
  }

  String scope() =>
      collabScopePath(container.read(hierarchyTreeProvider).selected);

  group('the presenter', () {
    testWidgets('announces itself and publishes what it shows', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, _session(me: 'ada'));

      expect(service.announcedScopes, [''], reason: 'the top of the design');
      expect(service.published.single.scopePath, '');
      expect(service.published.single.camera, isNotNull);
    });

    testWidgets('a trace and a scope go at once; a camera after it settles', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, _session(me: 'ada'));
      service.published.clear();

      container
          .read(traceOverlayProvider.notifier)
          .set(
            const TraceOverlay(
              mode: TraceOverlayMode.fanout,
              highlightedCellIds: {'u_cpu'},
              highlightedEdgeIds: {},
              highlightedBoundaryPortIds: {},
            ),
          );
      await tester.pump();
      expect(service.published.single.trace!.cellIds, {'u_cpu'});

      container.read(hierarchyTreeProvider.notifier).selectByPath(['u_cpu']);
      await tester.pump();
      expect(service.published.last.scopePath, 'u_cpu');

      final before = service.published.length;
      container
          .read(viewportTransformProvider.notifier)
          .pan(const Offset(10, 0));
      await tester.pump();
      expect(service.published, hasLength(before), reason: 'still settling');
      await tester.pump(kCollabPresenterCameraDebounce);
      expect(service.published, hasLength(before + 1));
    });

    testWidgets('a follower publishes nothing', (tester) async {
      await pump(tester);
      await emit(tester, _session(me: 'grace'));
      container.read(traceOverlayProvider.notifier).clear();
      container.read(hierarchyTreeProvider.notifier).selectByPath(['u_cpu']);
      await tester.pump(kCollabPresenterCameraDebounce);
      expect(service.published, isEmpty);
    });
  });

  group('a follower', () {
    const view = SchematicCollabPresenterView(
      scopePath: 'u_cpu',
      camera: SchematicCollabCamera(centerX: 100, centerY: 50, zoom: 2),
    );

    testWidgets("is taken to the presenter's scope and camera", (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, _session(me: 'grace', view: view));

      expect(scope(), 'u_cpu');
      final camera = container.read(viewportTransformProvider.notifier);
      final restore = camera.takePendingRestore(['u_cpu']);
      expect(restore, isNotNull, reason: 'applied when the layout lands');
      expect(restore!.zoom, 2);
      expect(
        const Offset(100, 50) * 2 + restore.offset,
        const Offset(400, 300),
        reason: "the presenter's centre at this canvas's centre",
      );
    });

    testWidgets('in the same scope the camera is framed at once', (
      tester,
    ) async {
      await pump(tester);
      await emit(
        tester,
        _session(
          me: 'grace',
          view: const SchematicCollabPresenterView(
            scopePath: '',
            camera: SchematicCollabCamera(centerX: 0, centerY: 0, zoom: 3),
          ),
        ),
      );
      expect(
        container.read(viewportTransformProvider),
        const ViewportTransform(zoom: 3, offset: Offset(400, 300)),
      );
      expect(container.read(collabFollowDetachedProvider), isFalse);
    });

    testWidgets('a pan detaches; the presenter is no longer applied until the '
        'follower resumes', (tester) async {
      await pump(tester);
      await emit(tester, _session(me: 'grace', view: view));

      container
          .read(viewportTransformProvider.notifier)
          .pan(const Offset(5, 5));
      await tester.pump();
      expect(container.read(collabFollowDetachedProvider), isTrue);

      // The presenter moves back to the top; the detached follower stays put.
      const top = SchematicCollabPresenterView(scopePath: '');
      await emit(tester, _session(me: 'grace', view: top));
      expect(scope(), 'u_cpu');

      container.read(collabFollowDetachedProvider.notifier).resume();
      await tester.pump();
      expect(scope(), '');
    });

    testWidgets('choosing another scope is a glance away too', (tester) async {
      await pump(tester);
      await emit(tester, _session(me: 'grace', view: view));
      container.read(hierarchyTreeProvider.notifier).selectByPath([]);
      await tester.pump();
      expect(container.read(collabFollowDetachedProvider), isTrue);
    });

    testWidgets('becoming the presenter, or the session ending, resumes', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, _session(me: 'grace', view: view));
      container.read(collabFollowDetachedProvider.notifier).detach();

      await emit(tester, _session(me: 'grace', presenterId: 'grace'));
      expect(container.read(collabFollowDetachedProvider), isFalse);

      container.read(collabFollowDetachedProvider.notifier).detach();
      await emit(tester, null);
      expect(container.read(collabFollowDetachedProvider), isFalse);
    });
  });

  group('the analysis panel', () {
    SchematicCollabPresenterView showing(String? panel) =>
        SchematicCollabPresenterView(scopePath: '', analysisPanel: panel);

    testWidgets('the presenter publishes the panel at the front of the dock', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, _session(me: 'ada'));
      container
          .read(analysisDockProvider.notifier)
          .open(AnalysisPanelKind.annotations);
      await tester.pump();
      expect(service.published.last.analysisPanel, 'annotations');
    });

    testWidgets('a follower with Pro gets the Pro panel, and loses it again '
        'when the presenter moves on', (tester) async {
      await pump(tester);
      await emit(tester, _session(me: 'grace', view: showing('cdc')));
      expect(container.read(analysisDockProvider), [AnalysisPanelKind.cdc]);

      await emit(tester, _session(me: 'grace', view: showing(null)));
      expect(container.read(analysisDockProvider), isEmpty);
    });

    testWidgets('a follower without Pro is not given a Pro panel', (
      tester,
    ) async {
      await pump(tester, pro: false);
      await emit(tester, _session(me: 'grace', view: showing('cdc')));
      expect(container.read(analysisDockProvider), isEmpty);

      await emit(tester, _session(me: 'grace', view: showing('annotations')));
      expect(
        container.read(analysisDockProvider),
        [AnalysisPanelKind.annotations],
        reason: 'open-core panels open for everyone',
      );
    });

    testWidgets("a panel the follower had open is the follower's to close", (
      tester,
    ) async {
      await pump(tester);
      container
          .read(analysisDockProvider.notifier)
          .open(AnalysisPanelKind.annotations);
      await emit(tester, _session(me: 'grace', view: showing('annotations')));
      await emit(tester, _session(me: 'grace', view: showing(null)));
      await emit(tester, null);
      expect(container.read(analysisDockProvider), [
        AnalysisPanelKind.annotations,
      ]);
    });

    testWidgets('the session closes what it opened when it ends', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, _session(me: 'grace', view: showing('fsm')));
      await emit(tester, null);
      expect(container.read(analysisDockProvider), isEmpty);
    });
  });
}
