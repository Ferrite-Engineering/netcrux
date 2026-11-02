// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/settings/widgets/settings_editors_section.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/editor_open_service.dart';

/// The hint is example text a user may copy into the empty field, so its
/// tokens must be the ones `EditorOpenService` substitutes.
void main() {
  Future<String> hintIn(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: const Scaffold(
            body: SettingsEditorsSection(currentCommand: ''),
          ),
        ),
      ),
    );
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    return field.decoration!.hintText!;
  }

  // The desktop theme never floats a field's label, so a field that holds a
  // value shows no `labelText` at all. The label has to be a row beside the
  // field, present while the field is full, and still the field's name.
  for (final locale in L10N.supportedLocales) {
    testWidgets(
      'the label in ${locale.toLanguageTag()} stays visible while the '
      'command is set, and names the field',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.binding.setSurfaceSize(const Size(900, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: cruxThemeForDevice(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
                highContrast: false,
                mobile: ThemeData.new,
                platform: TargetPlatform.macOS,
              ),
              locale: locale,
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: const Scaffold(
                body: SettingsEditorsSection(
                  currentCommand: 'my-editor {file}',
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final label = L10N
            .of(tester.element(find.byType(SettingsEditorsSection)))
            .settingsCxpEditorCommandLabel;
        expect(find.text('my-editor {file}'), findsOneWidget);
        expect(find.text(label), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byType(TextField))
              .decoration!
              .labelText,
          isNull,
          reason: 'a labelText would disappear once the field holds a value',
        );
        expect(
          tester.getSemantics(find.byType(TextField)).label,
          contains(label),
        );
        semantics.dispose();
      },
    );
  }

  for (final locale in L10N.supportedLocales) {
    testWidgets(
      'the hint in ${locale.toLanguageTag()} is a template the editor '
      'launcher fills in',
      (tester) async {
        final hint = await hintIn(tester, locale);

        late List<String> launched;
        final service = EditorOpenService(
          processRunner: (executable, arguments) async {
            launched = <String>[executable, ...arguments];
            return ProcessResult(0, 0, '', '');
          },
        );
        final result = await service.openSourceLocation(
          commandTemplate: hint,
          filePath: '/rtl/top.v',
          line: 42,
        );

        expect(result.honored, isTrue);
        expect(launched.join(' '), contains('/rtl/top.v:42'));
        expect(
          launched.join(' '),
          isNot(matches(RegExp('[<>{}]'))),
          reason: 'every token in the hint is one the launcher replaces',
        );
      },
    );
  }
}
