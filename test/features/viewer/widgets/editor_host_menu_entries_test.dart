// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/editor_host_kind.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/widgets/editor_host_menu_entries.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extensions_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/host_bridge/editor_host_providers.dart';

Future<List<SchematicContextMenuExtensionEntry>> _entriesFor(
  WidgetTester tester, {
  required EditorHostKind kind,
  Locale locale = const Locale('en'),
}) async {
  late List<SchematicContextMenuExtensionEntry> entries;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [editorHostKindProvider.overrideWithValue(kind)],
      child: MaterialApp(
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
            entries = buildEditorHostMenuEntries(
              ref,
              const SelectedElement.cell(cellId: 'u_alu'),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return entries;
}

void main() {
  testWidgets('an editor host gets Go to Source in Editor, free of tier', (
    tester,
  ) async {
    final entries = await _entriesFor(tester, kind: EditorHostKind.vscode);
    expect(entries, hasLength(1));
    expect(entries.single.id, 'editor-go-to-source');
    expect(entries.single.label, 'Go to Source in Editor');
    expect(entries.single.requiredTier, isNull);
    expect(entries.single.enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the entry is worded in every shipped language', (tester) async {
    for (final locale in L10N.supportedLocales) {
      final entries = await _entriesFor(
        tester,
        kind: EditorHostKind.vscode,
        locale: locale,
      );
      expect(entries.single.label, isNotEmpty, reason: '$locale');
      if (locale.languageCode != 'en') {
        expect(entries.single.label, isNot('Go to Source in Editor'));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the standalone app and a browser tab get no entry', (
    tester,
  ) async {
    expect(await _entriesFor(tester, kind: EditorHostKind.none), isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('open core registers the builder', () {
    expect(
      kOpenCoreSchematicContextMenuBuilders,
      contains(buildEditorHostMenuEntries),
    );
  });
}
