// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/annotations/providers/annotation_drafts_provider.dart';
import 'package:netcrux/features/annotations/providers/annotation_writing_provider.dart';
import 'package:netcrux/features/annotations/services/annotation_actions.dart';
import 'package:netcrux/features/inspector/providers/inspector_providers.dart';
import 'package:netcrux/features/inspector/widgets/inspector_panel.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/schematic_canvas_key_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';

import '../../../helpers/telemetry_test_overrides.dart';

const List<Locale> _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

const _graph = LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'cpu',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_alu',
        kind: CellKind.generic,
        type: 'alu',
        ports: [],
      ),
      SchematicCell(id: 'u_pc', kind: CellKind.generic, type: 'pc', ports: []),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: NetlistLayout(
    nodes: <NodePosition>[],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
  ),
);

const _alu = SelectedElement.cell(cellId: 'u_alu');
const _pc = SelectedElement.cell(cellId: 'u_pc');

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      ...netcruxTelemetryTestOverrides(),
      currentLaidOutGraphProvider.overrideWith((ref) async => _graph),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The Inspector beside a stand-in canvas: a focusable box keyed by the
/// tab's canvas key, whose Escape clears the selection as the schematic's
/// does.
Widget _host(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
  bool showInspector = true,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: Row(
          children: <Widget>[
            SizedBox(
              width: 200,
              height: 1000,
              child: Focus(
                debugLabel: 'canvas',
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    container.read(selectedElementProvider.notifier).clear();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: RepaintBoundary(
                  key: container.read(schematicCanvasKeyProvider),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            SizedBox(
              width: 420,
              height: 1000,
              child: showInspector
                  ? const InspectorPanel()
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Pumps [host] on a surface tall enough for a cell's sections and an
/// annotation form.
Future<void> _pump(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
}

Finder _titleOf(String key) =>
    find.byKey(ValueKey<String>('annotationTitleField-$key'));
Finder _bodyOf(String key) =>
    find.byKey(ValueKey<String>('annotationBodyField-$key'));

String get _newAluKey =>
    newAnnotationDraftKey(AnnotationTargetKind.cell, 'u_alu', null);

Future<L10N> _en() => L10N.delegate.load(const Locale('en'));

void main() {
  group('a new annotation', () {
    for (final locale in _locales) {
      testWidgets('renders the form in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        final l10n = await L10N.delegate.load(locale);
        final container = _container()
          ..read(selectedElementProvider.notifier).select(_alu);
        await _pump(tester, _host(container, locale: locale));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.annotationDialogTitle));
        await tester.pumpAndSettle();
        expect(find.text(l10n.inspectorNewAnnotation), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(3));
        expect(find.text(l10n.annotationDialogTitleLabel), findsOneWidget);
        expect(find.text(l10n.annotationDialogTitleHint), findsOneWidget);
        expect(find.text(l10n.annotationDialogBodyLabel), findsOneWidget);
        expect(
          tester.getTopLeft(_titleOf(_newAluKey)).dy,
          lessThan(tester.getTopLeft(_bodyOf(_newAluKey)).dy),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Add Annotation starts a draft with focus on its title and '
        'saves it to the tab store', (tester) async {
      final l10n = await _en();
      final container = _container();
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();

      // The opener every Add Annotation surface uses.
      startAnnotationInInspector(
        container,
        const AnnotationTarget(
          kind: AnnotationTargetKind.cell,
          targetId: 'u_alu',
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(selectedElementProvider).primary, _alu);
      final title = tester.widget<TextField>(_titleOf(_newAluKey));
      expect(title.focusNode!.hasFocus, isTrue);
      // The room hears "writing" from the moment the draft exists.
      expect(container.read(annotationWritingProvider), isTrue);

      await tester.enterText(_bodyOf(_newAluKey), 'Glitch at reset');
      await tester.tap(
        find.descendant(
          of: find.byType(CruxInspectorApplyBar),
          matching: find.text(l10n.annotationDialogTitle),
        ),
      );
      await tester.pumpAndSettle();

      final notes = container.read(annotationSnapshotProvider).annotations;
      expect(notes, hasLength(1));
      expect(notes.single.body, 'Glitch at reset');
      expect(notes.single.title, isNull);
      expect(notes.single.targetKind, AnnotationTargetKind.cell);
      expect(notes.single.targetId, 'u_alu');
      expect(notes.single.id, startsWith('an-'));
      expect(container.read(annotationDraftsProvider), isEmpty);
      expect(container.read(annotationWritingProvider), isFalse);
      // The saved note is now an editable section of its own.
      expect(_titleOf(notes.single.id), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add with neither title nor body is refused and says so', (
      tester,
    ) async {
      final l10n = await _en();
      final container = _container()
        ..read(selectedElementProvider.notifier).select(_alu);
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.annotationDialogTitle));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CruxInspectorApplyBar),
          matching: find.text(l10n.annotationDialogTitle),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.annotationDialogEmptyError), findsOneWidget);
      expect(container.read(annotationSnapshotProvider).annotations, isEmpty);
      // Typing in either field clears the message.
      await tester.enterText(_titleOf(_newAluKey), 'x');
      await tester.pumpAndSettle();
      expect(find.text(l10n.annotationDialogEmptyError), findsNothing);
    });

    testWidgets('a title alone saves, folded onto one line, with Enter', (
      tester,
    ) async {
      final container = _container()
        ..read(selectedElementProvider.notifier).select(_alu);
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();
      startAnnotationInInspector(
        container,
        const AnnotationTarget(
          kind: AnnotationTargetKind.cell,
          targetId: 'u_alu',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_titleOf(_newAluKey), '  Program   counter ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final note = container
          .read(annotationSnapshotProvider)
          .annotations
          .single;
      expect(note.title, 'Program counter');
      expect(note.body, isEmpty);
    });

    testWidgets('Discard drops the draft and the presence', (tester) async {
      final l10n = await _en();
      final container = _container()
        ..read(selectedElementProvider.notifier).select(_alu);
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.annotationDialogTitle));
      await tester.pumpAndSettle();
      expect(container.read(annotationWritingProvider), isTrue);
      await tester.tap(find.text(l10n.annotationUnsavedChangesDiscard));
      await tester.pumpAndSettle();
      expect(container.read(annotationDraftsProvider), isEmpty);
      expect(container.read(annotationWritingProvider), isFalse);
      expect(find.text(l10n.inspectorNewAnnotation), findsNothing);
    });
  });

  group('an existing annotation', () {
    const existing = Annotation(
      id: 'n1',
      targetKind: AnnotationTargetKind.cell,
      targetId: 'u_alu',
      title: 'ALU',
      body: 'before',
      createdAtMillis: 1,
      updatedAtMillis: 1,
      moduleName: 'cpu',
      colorArgb: 0xFF00AA88,
      sessionLayerId: 'session:ABC123',
      sessionLayerLabel: 'Session ABC123',
      hidden: true,
    );

    ProviderContainer seeded() {
      final container = _container();
      container.read(annotationStoreProvider).addAnnotation(existing);
      container.read(selectedElementProvider.notifier).select(_alu);
      return container;
    }

    testWidgets('Save keeps what the form does not show and can clear the '
        'title', (tester) async {
      final l10n = await _en();
      final container = seeded();
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();
      expect(find.text('ALU'), findsWidgets);
      // A clean form offers nothing to apply.
      final bar = tester.widget<CruxInspectorApplyBar>(
        find.byType(CruxInspectorApplyBar),
      );
      expect(bar.onApply, isNull);

      await tester.enterText(_titleOf('n1'), '');
      await tester.enterText(_bodyOf('n1'), 'after');
      expect(container.read(annotationWritingProvider), isTrue);
      await tester.tap(find.text(l10n.annotationDialogSaveButton));
      await tester.pumpAndSettle();
      final note = container
          .read(annotationSnapshotProvider)
          .annotations
          .single;
      expect(note.id, 'n1');
      expect(note.title, isNull);
      expect(note.body, 'after');
      expect(note.moduleName, 'cpu');
      expect(note.colorArgb, existing.colorArgb);
      expect(note.sessionLayerId, existing.sessionLayerId);
      expect(note.sessionLayerLabel, existing.sessionLayerLabel);
      expect(note.hidden, isTrue);
      expect(container.read(annotationWritingProvider), isFalse);
    });

    testWidgets('Revert restores the fields and stops the presence', (
      tester,
    ) async {
      final l10n = await _en();
      final container = seeded();
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();
      await tester.enterText(_bodyOf('n1'), 'half a thought');
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.inspectorRevert));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_bodyOf('n1')).controller!.text,
        'before',
      );
      expect(container.read(annotationWritingProvider), isFalse);
      expect(
        container.read(annotationSnapshotProvider).annotations.single.body,
        'before',
      );
    });

    testWidgets("another participant's note is read-only rows", (
      tester,
    ) async {
      final container = _container();
      container
          .read(annotationStoreProvider)
          .addAnnotation(
            const Annotation(
              id: 'theirs',
              targetKind: AnnotationTargetKind.cell,
              targetId: 'u_alu',
              title: 'Their note',
              body: 'Written in the review',
              author: 'grace',
              createdAtMillis: 1,
              updatedAtMillis: 1,
              authorId: 'p-grace',
            ),
          );
      container.read(selectedElementProvider.notifier).select(_alu);
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();
      expect(_titleOf('theirs'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('annotationReadOnly-theirs')),
        findsOneWidget,
      );
      expect(find.text('Written in the review'), findsOneWidget);
      expect(find.text('grace'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the Annotations panel Edit selects the element and focuses '
        'the title', (tester) async {
      final container = _container();
      container.read(annotationStoreProvider).addAnnotation(existing);
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();
      // The design's hierarchy is not loaded in this harness, so the reveal
      // cannot find the element: nothing changes.
      expect(openAnnotationInInspector(container, existing), isFalse);
      // With the element selected, the request is taken by its section.
      container.read(selectedElementProvider.notifier).select(_alu);
      await tester.pumpAndSettle();
      container.read(inspectorFocusRequestProvider.notifier).request('n1');
      container.read(inspectorControllerProvider).open();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_titleOf('n1')).focusNode!.hasFocus,
        isTrue,
      );
      expect(container.read(inspectorFocusRequestProvider), isNull);
    });
  });

  group('the held draft', () {
    testWidgets('holds the element while the selection moves, and follows it '
        'once applied', (tester) async {
      final l10n = await _en();
      final container = _container()
        ..read(selectedElementProvider.notifier).select(_alu);
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.annotationDialogTitle));
      await tester.pumpAndSettle();
      await tester.enterText(_bodyOf(_newAluKey), 'kept');

      container.read(selectedElementProvider.notifier).select(_pc);
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.inspectorHeldMessage('Cell u_alu')),
        findsOneWidget,
      );
      expect(find.text('Cell u_alu'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(CruxInspectorApplyBar),
          matching: find.text(l10n.annotationDialogTitle),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cell u_pc'), findsOneWidget);
      expect(find.text(l10n.inspectorHeldMessage('Cell u_alu')), findsNothing);
    });

    testWidgets('survives the dock showing another tab', (tester) async {
      final l10n = await _en();
      final container = _container()
        ..read(selectedElementProvider.notifier).select(_alu);
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.annotationDialogTitle));
      await tester.pumpAndSettle();
      await tester.enterText(_bodyOf(_newAluKey), 'still here');

      // The dock builds only its active tab: the Inspector is unmounted.
      await _pump(tester, _host(container, showInspector: false));
      await tester.pumpAndSettle();
      container.read(selectedElementProvider.notifier).select(_pc);
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(_bodyOf(_newAluKey)).controller!.text,
        'still here',
      );
      expect(
        find.text(l10n.inspectorHeldMessage('Cell u_alu')),
        findsOneWidget,
      );
      expect(container.read(annotationWritingProvider), isTrue);
    });

    testWidgets('Escape returns focus to the canvas and keeps the draft; a '
        'second Escape clears the selection', (tester) async {
      final l10n = await _en();
      final container = _container()
        ..read(selectedElementProvider.notifier).select(_alu);
      await _pump(tester, _host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.annotationDialogTitle));
      await tester.pumpAndSettle();
      await tester.enterText(_titleOf(_newAluKey), 'Half');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'canvas',
        reason: 'one Escape returns focus to the canvas',
      );
      expect(container.read(selectedElementProvider).primary, _alu);
      expect(container.read(annotationDraftsProvider), isNotEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        container.read(selectedElementProvider).primary,
        const SelectedElement.none(),
      );
      // The draft is still held on screen.
      expect(find.text('Cell u_alu'), findsOneWidget);
    });

    testWidgets('closing the tab stops the presence', (tester) async {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final tab = ProviderContainer(
        parent: root,
        overrides: [
          annotationDraftsProvider.overrideWith(AnnotationDraftsNotifier.new),
        ],
      );
      tab
          .read(annotationDraftsProvider.notifier)
          .startNew(
            kind: AnnotationTargetKind.cell,
            targetId: 'u',
            moduleName: null,
          );
      expect(root.read(annotationWritingProvider), isTrue);
      tab.dispose();
      await tester.pump();
      expect(root.read(annotationWritingProvider), isFalse);
    });
  });
}
