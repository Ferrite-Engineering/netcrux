import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/features/bookmarks/providers/annotation_writing_provider.dart';
import 'package:netcrux/features/bookmarks/widgets/annotation_dialog.dart';
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
  group('showAnnotationDialog', () {
    for (final locale in _locales) {
      testWidgets('renders localized chrome with no tier badge in '
          '${locale.toLanguageTag()}', (tester) async {
        final l10n = await L10N.delegate.load(locale);
        final (ctx, ref) = await _pumpHost(tester, locale: locale);
        unawaited(
          showAnnotationDialog(
            context: ctx,
            ref: ref,
            targetKind: BookmarkTargetKind.cell,
            targetId: 'top.alu',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(NetCruxFeatureTierBadge), findsNothing);
        expect(find.text(l10n.annotationDialogTitle), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Save returns an annotation carrying the entered body', (
      tester,
    ) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      final future = showAnnotationDialog(
        context: ctx,
        ref: ref,
        targetKind: BookmarkTargetKind.cell,
        targetId: 'top.alu',
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Glitch at reset');
      await tester.tap(find.text(l10n.bookmarkDialogSaveButton));
      await tester.pumpAndSettle();
      final ann = await future;
      expect(ann, isNotNull);
      expect(ann!.body, 'Glitch at reset');
      expect(ann.targetKind, BookmarkTargetKind.cell);
      expect(ann.targetId, 'top.alu');
      expect(tester.takeException(), isNull);
    });

    testWidgets('records the module on create and keeps it on edit', (
      tester,
    ) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      final created = showAnnotationDialog(
        context: ctx,
        ref: ref,
        targetKind: BookmarkTargetKind.cell,
        targetId: 'pc_reg',
        moduleName: 'cpu',
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Resets to 0');
      await tester.tap(find.text(l10n.bookmarkDialogSaveButton));
      await tester.pumpAndSettle();
      final ann = await created;
      expect(ann!.moduleName, 'cpu');

      final edited = showAnnotationDialog(
        context: ctx,
        ref: ref,
        targetKind: ann.targetKind,
        targetId: ann.targetId,
        moduleName: 'elsewhere',
        existing: ann,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Resets to 1');
      await tester.tap(find.text(l10n.bookmarkDialogSaveButton));
      await tester.pumpAndSettle();
      expect((await edited)!.moduleName, 'cpu');
    });

    testWidgets('an edit keeps the session, colour, attribution and layer '
        'visibility', (tester) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      const existing = Annotation(
        id: 'n1',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_alu',
        body: 'before',
        createdAtMillis: 1,
        updatedAtMillis: 1,
        authorId: 'p-grace',
        colorArgb: 0xFF00AA88,
        sessionLayerId: 'session:ABC123',
        sessionLayerLabel: 'Session ABC123 · 2026-10-08',
        hidden: true,
      );
      final edited = showAnnotationDialog(
        context: ctx,
        ref: ref,
        targetKind: existing.targetKind,
        targetId: existing.targetId,
        existing: existing,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'after');
      await tester.tap(find.text(l10n.bookmarkDialogSaveButton));
      await tester.pumpAndSettle();
      final note = (await edited)!;
      expect(note.body, 'after');
      expect(note.authorId, existing.authorId);
      expect(note.colorArgb, existing.colorArgb);
      expect(note.sessionLayerId, existing.sessionLayerId);
      expect(note.sessionLayerLabel, existing.sessionLayerLabel);
      expect(note.hidden, isTrue);
    });

    testWidgets('the room is told a note is being written while the dialog '
        'is open', (tester) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      final container = ProviderScope.containerOf(ctx);
      final future = showAnnotationDialog(
        context: ctx,
        ref: ref,
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u',
      );
      await tester.pumpAndSettle();
      expect(container.read(annotationWritingProvider), isTrue);
      await tester.tap(find.text(l10n.bookmarkDialogCancelButton));
      await tester.pumpAndSettle();
      await future;
      expect(container.read(annotationWritingProvider), isFalse);
    });

    testWidgets('Cancel returns null', (tester) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      final future = showAnnotationDialog(
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

    testWidgets('Save with an empty body is rejected (dialog stays open)', (
      tester,
    ) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      unawaited(
        showAnnotationDialog(
          context: ctx,
          ref: ref,
          targetKind: BookmarkTargetKind.cell,
          targetId: 'top.alu',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.bookmarkDialogSaveButton));
      await tester.pumpAndSettle();
      // Body is required → _submit early-returns without popping.
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(l10n.bookmarkDialogCancelButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('dirty cancel prompts to discard; keep editing stays open', (
      tester,
    ) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await _pumpHost(tester);
      final future = showAnnotationDialog(
        context: ctx,
        ref: ref,
        targetKind: BookmarkTargetKind.cell,
        targetId: 'top.alu',
      );
      await tester.pumpAndSettle();

      // Dirty the form.
      await tester.enterText(find.byType(TextField).first, 'Glitch at reset');
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
      expect(find.text('Glitch at reset'), findsOneWidget);

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
      final future = showAnnotationDialog(
        context: ctx,
        ref: ref,
        targetKind: BookmarkTargetKind.cell,
        targetId: 'top.alu',
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
