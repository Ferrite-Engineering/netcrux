// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/features/workspace/widgets/browser_empty_canvas_content.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const _buildInfo = ApplicationBuildInfo(
  version: '9.9.9',
  buildNumber: '7',
  gitShortSha: 'abc1234',
  os: 'web',
  architecture: 'wasm',
  flutterSdkVersion: '3.44.8',
  dartSdkVersion: '3.12.2',
);

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback onOpen,
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aboutBuildInfoProvider.overrideWith((ref) async => _buildInfo),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: BrowserEmptyCanvasContent(onOpenNetlistJson: onOpen),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers only Open Netlist JSON, and it opens the picker flow', (
    tester,
  ) async {
    var opened = 0;
    await _pump(tester, onOpen: () => opened++);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    await tester.tap(find.text('Open Netlist JSON…'));
    await tester.pump();
    expect(opened, 1);
    expect(find.textContaining('Yosys write_json'), findsOneWidget);
    expect(find.text('v9.9.9'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in const ['zh', 'ja', 'ko']) {
    testWidgets('renders in $locale without exceptions', (tester) async {
      await _pump(tester, onOpen: () {}, locale: Locale(locale));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
