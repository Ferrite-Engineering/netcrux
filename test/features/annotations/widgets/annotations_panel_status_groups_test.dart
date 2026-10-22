// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/crux_annotations.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/features/annotations/providers/annotation_statuses_provider.dart';
import 'package:netcrux/features/annotations/widgets/annotations_panel.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/schematic/annotation_callout_seams.dart';
import 'package:netcrux/services/session/annotation_state.dart';

Annotation _note(String id, {String? layer}) => Annotation(
  id: id,
  targetKind: AnnotationTargetKind.cell,
  targetId: 'u_$id',
  title: 'Note $id',
  body: '',
  createdAtMillis: 1,
  updatedAtMillis: 1,
  sessionLayerId: layer,
  sessionLayerLabel: layer == null ? null : 'Session $layer',
);

const _statuses = <String, CruxAnnotationStatus>{
  'here': CruxAnnotationStatus.resolved,
  'drift': CruxAnnotationStatus.drifted,
  'away': CruxAnnotationStatus.orphaned,
  'gone': CruxAnnotationStatus.unresolved,
  'layered': CruxAnnotationStatus.resolved,
  'awayLayered': CruxAnnotationStatus.orphaned,
};

List<Annotation> _notes() => <Annotation>[
  _note('gone'),
  _note('away'),
  _note('here'),
  _note('layered', layer: 'L'),
  _note('drift'),
  _note('awayLayered', layer: 'L'),
];

void main() {
  test(
    'rows: shown notes and layers, then outside the scope, then missing',
    () {
      final rows = annotationPanelRows(_notes(), statuses: _statuses);
      expect(
        <String>[
          for (final r in rows)
            r.annotation?.id ??
                (r.groupStatus != null
                    ? 'group:${r.groupStatus!.name}:${r.layerNotes}'
                    : 'layer:${r.layerId}:${r.layerNotes}'),
        ],
        <String>[
          'here',
          'drift',
          'layer:L:1',
          'layered',
          'group:orphaned:2',
          'away',
          'awayLayered',
          'group:unresolved:1',
          'gone',
        ],
      );
    },
  );

  test('without statuses every note is shown, as in 1.1', () {
    final rows = annotationPanelRows(_notes());
    expect(rows.where((r) => r.groupStatus != null), isEmpty);
    expect(rows.where((r) => r.annotation != null), hasLength(6));
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<Override> extra = const <Override>[],
    Locale locale = const Locale('en'),
  }) async {
    final container = ProviderContainer(
      overrides: [
        annotationStatusesProvider.overrideWithValue(_statuses),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    container.read(annotationStateProvider.notifier).setAnnotations(_notes());
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
    return container;
  }

  testWidgets('the panel heads the groups and marks drift in words', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(find.text('Outside the current scope (2)'), findsOneWidget);
    expect(find.text('Missing from this design (1)'), findsOneWidget);
    expect(find.byType(CruxAnnotationGroup), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('annotationDrifted-drift')),
      findsOneWidget,
    );
    expect(find.text('Drifted'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp('Drifted: the element changed since this note was written'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('the group headers and the marker render in the CJK locales', (
    tester,
  ) async {
    for (final (locale, outside, missing, drifted)
        in <
          (
            Locale,
            String,
            String,
            String,
          )
        >[
          (const Locale('zh', 'CN'), '当前作用域之外 (2)', '此设计中已不存在 (1)', '已变化'),
          (const Locale('ja'), '現在のスコープの外 (2)', 'この設計にない (1)', '変化あり'),
          (const Locale('ko'), '현재 범위 밖 (2)', '이 설계에 없음 (1)', '변경됨'),
        ]) {
      await pump(tester, locale: locale);
      expect(find.text(outside), findsOneWidget, reason: '$locale');
      expect(find.text(missing), findsOneWidget, reason: '$locale');
      expect(find.text(drifted), findsOneWidget, reason: '$locale');
      expect(tester.takeException(), isNull);
    }
  });

  // Tier law: annotations, their panel, their groups and the drift marker are
  // open core. Nothing here is overridden by a Pro overlay: no proOverrides,
  // the beta flag off, the open-core tier, and the callout seams at their
  // open-core defaults.
  testWidgets('every row, group and drift marker renders in open core', (
    tester,
  ) async {
    final container = await pump(
      tester,
      extra: <Override>[
        betaPeriodProvider.overrideWithValue(false),
        licenseTierProvider.overrideWithValue(LicenseTier.openCore),
      ],
    );
    expect(container.read(schematicCalloutLayerBuilderProvider), isNull);
    expect(container.read(toggleAnnotationCalloutsOpenerProvider), isNull);
    for (final id in _statuses.keys) {
      expect(
        find.byKey(ValueKey<String>('annotationRow-$id')),
        findsOneWidget,
        reason: id,
      );
    }
    expect(find.text('Outside the current scope (2)'), findsOneWidget);
    expect(find.text('Missing from this design (1)'), findsOneWidget);
    expect(find.text('Drifted'), findsOneWidget);
  });
}
