import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/features/bookmarks/widgets/bookmark_dialog.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_feature_tier_badge.dart';

const List<Locale> _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

Future<(BuildContext, WidgetRef)> _pumpHost(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  late BuildContext ctx;
  late WidgetRef wref;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const <LocalizationsDelegate<Object?>>[
          L10N.delegate,
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: _locales,
        home: Consumer(
          builder: (context, ref, _) {
            wref = ref;
            return Scaffold(
              body: Builder(
                builder: (innerContext) {
                  ctx = innerContext;
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

void main() {
  group('showBookmarkDialog', () {
    for (final locale in _locales) {
      testWidgets('renders localized chrome with no tier badge in '
          '${locale.toLanguageTag()}', (tester) async {
        final l10n = await L10N.delegate.load(locale);
        final (ctx, ref) = await _pumpHost(tester, locale: locale);
        unawaited(
          showBookmarkDialog(
            context: ctx,
            ref: ref,
            targetKind: BookmarkTargetKind.cell,
            targetId: 'top.alu',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(NetCruxFeatureTierBadge), findsNothing);
        expect(find.text(l10n.bookmarkDialogTitle), findsOneWidget);
        // Name and Note. The Color field is gone: it only tinted the row's
        // dot in the list and was never drawn on the schematic.
        expect(find.byType(TextField), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('has no Color field', (tester) async {
      final (ctx, ref) = await _pumpHost(tester);
      unawaited(
        showBookmarkDialog(
          context: ctx,
          ref: ref,
          targetKind: BookmarkTargetKind.cell,
          targetId: 'top.alu',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Color (optional)'), findsNothing);
      expect(find.text('#RRGGBB'), findsNothing);
    });

    testWidgets('a new bookmark records the module it was made in; an edit '
        'keeps it', (tester) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      final created = showBookmarkDialog(
        context: ctx,
        ref: ref,
        targetKind: BookmarkTargetKind.cell,
        targetId: 'pc_reg',
        moduleName: 'cpu',
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'PC');
      await tester.enterText(find.byType(TextField).last, 'Reset value');
      await tester.tap(find.text(l10n.bookmarkDialogSaveButton));
      await tester.pumpAndSettle();
      final bookmark = await created;
      expect(bookmark!.moduleName, 'cpu');
      expect(bookmark.note, 'Reset value');
      expect(bookmark.toJson().keys, isNot(contains('colorHex')));

      final edited = showBookmarkDialog(
        context: ctx,
        ref: ref,
        targetKind: bookmark.targetKind,
        targetId: bookmark.targetId,
        moduleName: 'elsewhere',
        existing: bookmark,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Program counter');
      await tester.tap(find.text(l10n.bookmarkDialogSaveButton));
      await tester.pumpAndSettle();
      final after = await edited;
      expect(after!.name, 'Program counter');
      expect(after.moduleName, 'cpu');
    });

    testWidgets('Save returns a bookmark carrying the entered fields', (
      tester,
    ) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      final future = showBookmarkDialog(
        context: ctx,
        ref: ref,
        targetKind: BookmarkTargetKind.cell,
        targetId: 'top.alu',
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'My mark');
      await tester.tap(find.text(l10n.bookmarkDialogSaveButton));
      await tester.pumpAndSettle();
      final bm = await future;
      expect(bm, isNotNull);
      expect(bm!.name, 'My mark');
      expect(bm.targetKind, BookmarkTargetKind.cell);
      expect(bm.targetId, 'top.alu');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cancel returns null', (tester) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      final future = showBookmarkDialog(
        context: ctx,
        ref: ref,
        targetKind: BookmarkTargetKind.net,
        targetId: 'top:net:foo',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.bookmarkDialogCancelButton));
      await tester.pumpAndSettle();
      expect(await future, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Save with an empty name is rejected (dialog stays open)', (
      tester,
    ) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      unawaited(
        showBookmarkDialog(
          context: ctx,
          ref: ref,
          targetKind: BookmarkTargetKind.cell,
          targetId: 'top.alu',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.bookmarkDialogSaveButton));
      await tester.pumpAndSettle();
      // Name is required → _submit early-returns without popping.
      expect(find.byType(AlertDialog), findsOneWidget);
      // Clean up the still-open dialog so no future dangles.
      await tester.tap(find.text(l10n.bookmarkDialogCancelButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('dirty cancel prompts to discard; keep editing stays open', (
      tester,
    ) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      final future = showBookmarkDialog(
        context: ctx,
        ref: ref,
        targetKind: BookmarkTargetKind.cell,
        targetId: 'top.alu',
      );
      await tester.pumpAndSettle();

      // Dirty the form.
      await tester.enterText(find.byType(TextField).first, 'My mark');
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.bookmarkDialogCancelButton));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.bookmarkAnnotationUnsavedChangesTitle),
        findsOneWidget,
      );

      // "Keep editing" returns to the dialog with input intact.
      await tester.tap(
        find.text(l10n.bookmarkAnnotationUnsavedChangesKeep),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.bookmarkAnnotationUnsavedChangesTitle),
        findsNothing,
      );
      expect(find.text('My mark'), findsOneWidget);

      // "Discard" closes the dialog and resolves null.
      await tester.tap(find.text(l10n.bookmarkDialogCancelButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(l10n.bookmarkAnnotationUnsavedChangesDiscard),
      );
      await tester.pumpAndSettle();
      expect(await future, isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clean cancel closes without a prompt', (tester) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      final future = showBookmarkDialog(
        context: ctx,
        ref: ref,
        targetKind: BookmarkTargetKind.net,
        targetId: 'top:net:foo',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.bookmarkDialogCancelButton));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.bookmarkAnnotationUnsavedChangesTitle),
        findsNothing,
      );
      expect(await future, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
