// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/features/annotations/services/annotation_actions.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/telemetry/annotation_telemetry.dart';
import 'package:netcrux/services/telemetry/telemetry_event_catalog.dart';

class _RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  Iterable<TelemetryEvent> all(String name) =>
      events.where((e) => e.name == name);
}

/// Fails unless [event] is in the shared catalog and every property it carries
/// is declared there with a value from the declared vocabulary.
void _assertInCatalog(TelemetryEvent event) {
  final entry = kNetcruxEventCatalog.firstWhere(
    (e) => e.name == event.name,
    orElse: () => throw StateError('${event.name} is not in the catalog'),
  );
  event.properties.forEach((key, value) {
    expect(entry.propertyKeys, contains(key));
    if (entry.enumeratedValues.containsKey(key)) {
      expect(
        entry.enumeratedValues[key],
        contains(value),
        reason: '${event.name}.$key = "$value" is outside the catalog set',
      );
    }
  });
}

void main() {
  late _RecordingTelemetryService telemetry;

  setUp(() => telemetry = _RecordingTelemetryService());

  Future<(BuildContext, WidgetRef)> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    late WidgetRef wref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
        child: MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<Object?>>[
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10N.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              wref = ref;
              return Scaffold(
                body: Builder(
                  builder: (inner) {
                    ctx = inner;
                    return const SizedBox.shrink();
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (ctx, wref);
  }

  const target = AnnotationTarget(
    kind: AnnotationTargetKind.cell,
    targetId: 'top.alu',
  );

  group('annotation.added', () {
    testWidgets('saving a titled annotation records the bare event', (
      tester,
    ) async {
      final (ctx, ref) = await pumpHost(tester);

      openAddAnnotationDialog(ctx, ref, target: target);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('annotationDialogTitleField')),
        'my marker',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      final event = telemetry.all('annotation.added').single;
      expect(event.properties, isEmpty);
      // The title the user typed and the element it anchors to are theirs.
      expect(event.toString(), isNot(contains('my marker')));
      expect(event.toString(), isNot(contains('top.alu')));
      _assertInCatalog(event);
    });

    testWidgets('saving an annotation body records nothing of the text', (
      tester,
    ) async {
      final (ctx, ref) = await pumpHost(tester);

      openAddAnnotationDialog(ctx, ref, target: target);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('annotationDialogBodyField')),
        'a private note',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      final event = telemetry.all('annotation.added').single;
      expect(event.properties, isEmpty);
      expect(event.toString(), isNot(contains('a private note')));
      _assertInCatalog(event);
    });

    testWidgets('cancelling the dialog records nothing', (tester) async {
      final (ctx, ref) = await pumpHost(tester);

      openAddAnnotationDialog(ctx, ref, target: target);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(telemetry.all('annotation.added'), isEmpty);
    });

    test('the catalog declares annotation.added with no properties', () {
      final entry = kNetcruxEventCatalog.firstWhere(
        (e) => e.name == 'annotation.added',
      );
      expect(entry.propertyKeys, isEmpty);
    });

    test('recordAnnotationAdded writes the bare event', () {
      recordAnnotationAdded(telemetry);
      expect(telemetry.all('annotation.added').single.properties, isEmpty);
    });
  });
}
