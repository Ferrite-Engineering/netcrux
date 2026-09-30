// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

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
