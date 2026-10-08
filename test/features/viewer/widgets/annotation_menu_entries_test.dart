// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/widgets/annotation_menu_entries.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';

/// Pumps a host in [locale] and returns the entries the builder emits for
/// [target], built with the host's own ref.
Future<List<SchematicContextMenuExtensionEntry>> _entriesFor(
  WidgetTester tester,
  SelectedElement target, {
  Locale locale = const Locale('en'),
  ProviderContainer? container,
}) async {
  late List<SchematicContextMenuExtensionEntry> entries;
  final host = MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      L10N.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: L10N.supportedLocales,
    home: Consumer(
      builder: (context, ref, _) {
        entries = buildAnnotationMenuEntries(ref, target);
        return const SizedBox.shrink();
      },
    ),
  );
  await tester.pumpWidget(
    container == null
        ? ProviderScope(child: host)
        : UncontrolledProviderScope(container: container, child: host),
  );
  return entries;
}

void main() {
  group('buildAnnotationMenuEntries', () {
    testWidgets('emits no entries for an empty selection', (tester) async {
      final entries = await _entriesFor(tester, const SelectedElement.none());
      expect(entries, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('emits Add Annotation for a cell selection', (
      tester,
    ) async {
      final entries = await _entriesFor(
        tester,
        const SelectedElement.cell(cellId: 'u_alu'),
      );
      expect(entries, hasLength(1));
      expect(entries.single.id, 'add-annotation-cell-u_alu');
      expect(entries.single.label, contains('Annotation'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('carries no tier: annotations are free', (
      tester,
    ) async {
      final entries = await _entriesFor(
        tester,
        const SelectedElement.cell(cellId: 'u_alu'),
      );
      for (final entry in entries) {
        expect(entry.requiredTier, isNull, reason: entry.id);
        expect(entry.enabled, isTrue, reason: entry.id);
      }
    });

    testWidgets('encodes wire selection as a net target', (tester) async {
      final entries = await _entriesFor(
        tester,
        const SelectedElement.wire(edgeId: 'e_4', netId: 4),
      );
      expect(entries, hasLength(1));
      expect(entries.single.id, 'add-annotation-net-e_4');
    });

    testWidgets('offers Show Annotation first on an annotated element', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(annotationStoreProvider)
          .addAnnotation(
            const Annotation(
              id: 'an-1',
              targetKind: AnnotationTargetKind.cell,
              targetId: 'u_alu',
              body: 'note',
              createdAtMillis: 1,
              updatedAtMillis: 1,
            ),
          );

      final annotated = await _entriesFor(
        tester,
        const SelectedElement.cell(cellId: 'u_alu'),
        container: container,
      );
      expect(annotated.map((e) => e.id), <String>[
        'show-annotation-cell-u_alu',
        'add-annotation-cell-u_alu',
      ]);

      final other = await _entriesFor(
        tester,
        const SelectedElement.cell(cellId: 'u_other'),
        container: container,
      );
      expect(other.map((e) => e.id), <String>[
        'add-annotation-cell-u_other',
      ]);
    });

    for (final locale in L10N.supportedLocales) {
      testWidgets('labels come from the ${locale.toLanguageTag()} catalog', (
        tester,
      ) async {
        final l10n = await L10N.delegate.load(locale);
        final entries = await _entriesFor(
          tester,
          const SelectedElement.cell(cellId: 'u_alu'),
          locale: locale,
        );
        expect(entries.map((e) => e.label), <String>[
          l10n.annotationMenuAdd,
        ]);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
