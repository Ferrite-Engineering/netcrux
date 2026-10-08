import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/features/annotations/widgets/annotations_panel.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/annotation_state.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';
import 'package:netcrux/services/session/in_session_annotation_store.dart';
import 'package:netcrux/shared/widgets/netcrux_feature_tier_badge.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap(Widget child, Locale locale) {
  return ProviderScope(
    overrides: [
      annotationStoreProvider.overrideWith(
        InSessionAnnotationStore.new,
      ),
      annotationSnapshotProvider.overrideWith(
        (ref) => ref.watch(annotationStateProvider),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('AnnotationsPanel', () {
    testWidgets('renders empty state when no annotations', (tester) async {
      await tester.pumpWidget(
        _wrap(const AnnotationsPanel(), const Locale('en')),
      );
      await tester.pump();
      expect(find.text('Annotations'), findsOneWidget);
      expect(find.textContaining('No annotations yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists an annotation added via the store', (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            annotationStoreProvider.overrideWith(
              InSessionAnnotationStore.new,
            ),
            annotationSnapshotProvider.overrideWith(
              (ref) => ref.watch(annotationStateProvider),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              L10N.delegate,
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(body: AnnotationsPanel());
              },
            ),
          ),
        ),
      );
      container
          .read(annotationStoreProvider)
          .addAnnotation(
            const Annotation(
              id: 'a1',
              targetKind: AnnotationTargetKind.cell,
              targetId: 'u_alu',
              body: 'ALU output is glitchy at reset.',
              createdAtMillis: 100,
              updatedAtMillis: 100,
            ),
          );
      await tester.pump();
      expect(
        find.textContaining('ALU output is glitchy at reset'),
        findsOneWidget,
      );
      expect(find.byType(NetCruxFeatureTierBadge), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final locale in _locales) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(_wrap(const AnnotationsPanel(), locale));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'renders markdown bodies via flutter_markdown_plus without exception',
      (tester) async {
        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              annotationStoreProvider.overrideWith(
                InSessionAnnotationStore.new,
              ),
              annotationSnapshotProvider.overrideWith(
                (ref) => ref.watch(annotationStateProvider),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: const [
                L10N.delegate,
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en')],
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(body: AnnotationsPanel());
                },
              ),
            ),
          ),
        );
        // A body exercising the common markdown features: heading,
        // paragraph, bold/italic, inline code, link, code block, and
        // an unordered list. flutter_markdown_plus should render each
        // without throwing.
        const richBody = '''
# Title

A *paragraph* with **bold**, `inline code`, and a [link](https://example.com).

```
code block
```

- item one
- item two
''';
        container
            .read(annotationStoreProvider)
            .addAnnotation(
              const Annotation(
                id: 'rich',
                targetKind: AnnotationTargetKind.cell,
                targetId: 'u_decoder',
                body: richBody,
                createdAtMillis: 100,
                updatedAtMillis: 100,
              ),
            );
        await tester.pump();
        // Heading text should appear in the rendered output even
        // though the surrounding markdown syntax is consumed.
        expect(find.textContaining('Title'), findsOneWidget);
        expect(find.textContaining('paragraph'), findsOneWidget);
        expect(find.textContaining('item one'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
