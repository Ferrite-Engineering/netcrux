// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/features/annotations/providers/annotation_schematic_markers.dart';
import 'package:netcrux/features/annotations/widgets/annotations_panel.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/schematic/schematic_annotation_markers_provider.dart';
import 'package:netcrux/services/session/annotation_state.dart';

const _layer = 'session:ABC123';

Annotation _note(
  String id, {
  String? layer,
  String? authorId,
  bool hidden = false,
}) => Annotation(
  id: id,
  targetKind: AnnotationTargetKind.cell,
  targetId: 'u_$id',
  body: 'note $id',
  createdAtMillis: 1,
  updatedAtMillis: 1,
  authorId: authorId,
  colorArgb: layer == null ? null : 0xFF2266AA,
  sessionLayerId: layer,
  sessionLayerLabel: layer == null ? null : 'Session ABC123 · 2026-10-08',
  hidden: hidden,
);

/// Session layers in the Annotations panel: one meeting's notes under one
/// header, hidden or deleted as a unit, and others' notes read-only.
void main() {
  group('annotationPanelRows', () {
    test('notes of your own first, then each layer under its header', () {
      final rows = annotationPanelRows([
        _note('a', layer: _layer),
        _note('b'),
        _note('c', layer: 'session:OTHER'),
        _note('d', layer: _layer),
      ]);
      expect(
        [for (final r in rows) r.annotation?.id ?? 'header:${r.layerId}'],
        [
          'b',
          'header:$_layer',
          'a',
          'd',
          'header:session:OTHER',
          'c',
        ],
      );
      expect(rows[1].layerNotes, 2);
    });
  });

  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester,
    List<Annotation> notes, {
    Locale locale = const Locale('en'),
  }) async {
    container = ProviderContainer(
      overrides: [
        // As the tab overrides bind it.
        schematicAnnotationMarkersProvider.overrideWith(
          annotationSchematicMarkers,
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(annotationStateProvider.notifier)
        .setAnnotations(
          notes,
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10N.supportedLocales,
          home: const Scaffold(body: AnnotationsPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<Annotation> notes() =>
      container.read(annotationStateProvider).annotations;

  testWidgets('a layer hides from the canvas as a unit, and shows again', (
    tester,
  ) async {
    await pump(tester, [_note('a', layer: _layer), _note('b', layer: _layer)]);
    expect(find.text('Session ABC123 · 2026-10-08'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide layer'));
    await tester.pumpAndSettle();
    expect(notes().every((n) => n.hidden), isTrue);
    expect(
      container.read(schematicAnnotationMarkersProvider),
      isNull,
      reason: 'hidden notes leave the canvas',
    );

    await tester.tap(find.byTooltip('Show layer'));
    await tester.pumpAndSettle();
    expect(notes().any((n) => n.hidden), isFalse);
  });

  testWidgets('a layer deletes as a unit, after asking', (tester) async {
    await pump(tester, [
      _note('mine'),
      _note('a', layer: _layer),
      _note('b', layer: _layer),
    ]);
    await tester.tap(find.byTooltip('Delete layer'));
    await tester.pumpAndSettle();
    expect(find.text('Its 2 notes are removed from this design.'), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete layer'));
    await tester.pumpAndSettle();
    expect(notes().map((n) => n.id), ['mine']);
  });

  testWidgets("somebody else's note can be deleted but not edited", (
    tester,
  ) async {
    await pump(tester, [_note('theirs', layer: _layer, authorId: 'grace')]);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Edit Annotation…'), findsNothing);
    expect(find.text('Delete Annotation'), findsOneWidget);
  });

  testWidgets('a note of your own is editable', (tester) async {
    await pump(tester, [_note('mine', layer: _layer)]);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Edit Annotation…'), findsOneWidget);
  });

  testWidgets('a layer renders in every locale', (tester) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await pump(tester, [
        _note('mine'),
        _note('theirs', layer: _layer, authorId: 'grace'),
      ], locale: locale);
      expect(tester.takeException(), isNull, reason: '$locale');
      expect(find.byIcon(Icons.layers_outlined), findsOneWidget);
    }
  });
}
