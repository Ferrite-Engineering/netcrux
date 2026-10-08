// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/domain/models/bookmark_annotation_target.dart';
import 'package:netcrux/features/bookmarks/services/bookmark_annotation_actions.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/telemetry/annotation_telemetry.dart';
import 'package:netcrux/services/telemetry/netcrux_telemetry_vocabulary.dart';
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

  const target = BookmarkAnnotationTarget(
    kind: BookmarkTargetKind.cell,
    targetId: 'top.alu',
  );

  group('annotation.added', () {
    testWidgets('saving a bookmark records kind: bookmark', (tester) async {
      final (ctx, ref) = await pumpHost(tester);

      openAddBookmarkDialog(ctx, ref, target: target);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'my marker');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      final event = telemetry.all('annotation.added').single;
      expect(event.properties, <String, Object?>{'kind': 'bookmark'});
      // The label the user typed and the element it anchors to are theirs.
      expect(event.toString(), isNot(contains('my marker')));
      expect(event.toString(), isNot(contains('top.alu')));
      _assertInCatalog(event);
    });

    testWidgets('saving an annotation records kind: annotation', (
      tester,
    ) async {
      final (ctx, ref) = await pumpHost(tester);

      openAddAnnotationDialog(ctx, ref, target: target);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'a private note');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      final event = telemetry.all('annotation.added').single;
      expect(event.properties, <String, Object?>{'kind': 'annotation'});
      expect(event.toString(), isNot(contains('a private note')));
      _assertInCatalog(event);
    });

    testWidgets('cancelling the dialog records nothing', (tester) async {
      final (ctx, ref) = await pumpHost(tester);

      openAddBookmarkDialog(ctx, ref, target: target);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(telemetry.all('annotation.added'), isEmpty);
    });

    test('every NetcruxAnnotationKind is a catalog token', () {
      final entry = kNetcruxEventCatalog.firstWhere(
        (e) => e.name == 'annotation.added',
      );
      for (final kind in NetcruxAnnotationKind.values) {
        expect(
          entry.enumeratedValues['kind'],
          contains(telemetryEnumToken(kind)),
        );
      }
    });

    test('recordAnnotationAdded writes the kind token and nothing else', () {
      recordAnnotationAdded(telemetry, NetcruxAnnotationKind.annotation);
      expect(telemetry.all('annotation.added').single.properties, {
        'kind': 'annotation',
      });
    });
  });
}
