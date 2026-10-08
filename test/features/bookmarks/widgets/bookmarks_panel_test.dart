import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/features/bookmarks/widgets/bookmarks_panel.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/bookmark_annotation_state.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';
import 'package:netcrux/services/session/in_session_bookmark_annotation_store.dart';
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
      bookmarkAnnotationStoreProvider.overrideWith(
        InSessionBookmarkAnnotationStore.new,
      ),
      bookmarkAnnotationSnapshotProvider.overrideWith(
        (ref) => ref.watch(bookmarkAnnotationStateProvider),
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
  group('BookmarksPanel', () {
    testWidgets('renders empty state when no bookmarks are present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const BookmarksPanel(), const Locale('en')),
      );
      await tester.pump();
      expect(find.text('Bookmarks'), findsOneWidget);
      // The empty-state message starts with "No bookmarks yet."
      expect(find.textContaining('No bookmarks yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists a bookmark added via the store', (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookmarkAnnotationStoreProvider.overrideWith(
              InSessionBookmarkAnnotationStore.new,
            ),
            bookmarkAnnotationSnapshotProvider.overrideWith(
              (ref) => ref.watch(bookmarkAnnotationStateProvider),
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
                return const Scaffold(body: BookmarksPanel());
              },
            ),
          ),
        ),
      );
      container
          .read(bookmarkAnnotationStoreProvider)
          .addBookmark(
            const Bookmark(
              id: 'b1',
              name: 'Clock root',
              targetKind: BookmarkTargetKind.net,
              targetId: 'e_clk',
              createdAtMillis: 100,
            ),
          );
      await tester.pump();
      expect(find.text('Clock root'), findsOneWidget);
      expect(find.byType(NetCruxFeatureTierBadge), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final locale in _locales) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(_wrap(const BookmarksPanel(), locale));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
