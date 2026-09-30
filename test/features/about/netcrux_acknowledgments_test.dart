// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_about_dialog/crux_about_dialog.dart';
import 'package:crux_app_info/crux_app_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/about/netcrux_vendored_licenses.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/features/about/netcrux_about_dialog.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const _stubBuildInfo = ApplicationBuildInfo(
  version: '1.2.3',
  buildNumber: '42',
  gitShortSha: 'abc1234',
  os: 'macOS 15.0',
  architecture: 'arm64',
  flutterSdkVersion: '3.29.0',
  dartSdkVersion: '3.7.0',
);

Widget _buildApp() => ProviderScope(
  overrides: [aboutBuildInfoProvider.overrideWith((_) async => _stubBuildInfo)],
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Center(
          child: ElevatedButton(
            onPressed: () => NetcruxAboutDialog.openAdaptive(context, ref),
            child: const Text('open-about'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('open-about'));
  await tester.pumpAndSettle();
}

void main() {
  group('vendored license list', () {
    test('names elkjs and points at the shipped EPL text', () {
      expect(kNetcruxVendoredLicenses, hasLength(1));
      final elk = kNetcruxVendoredLicenses.single;
      expect(elk.packageName, contains('elkjs'));
      expect(elk.licenseAssetPath, 'assets/elk/LICENSE.epl-2.0.txt');
    });

    test('registers into LicenseRegistry alongside the pub packages', () async {
      LicenseRegistry.reset();
      addTearDown(LicenseRegistry.reset);
      registerCruxVendoredLicenses(kNetcruxVendoredLicenses);

      // The real asset is readable under the test bundle, so this exercises
      // the actual file rather than a mock — which is the point: it proves
      // the shipped text is what the Acknowledgments page will render.
      final entries = await LicenseRegistry.licenses.toList();
      final elk = entries.where(
        (e) => e.packages.any((p) => p.contains('elkjs')),
      );
      expect(elk, hasLength(1));
      expect(
        elk.single.paragraphs.first.text,
        contains('Eclipse Public License'),
      );
    });
  });

  group('Acknowledgments action', () {
    testWidgets('opens the license page', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);

      // The action row scrolls: with eight buttons the last two sit below
      // the fold on the 800x600 test surface, and tapping an off-screen
      // finder silently hits nothing.
      await tester.ensureVisible(find.text('Acknowledgments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acknowledgments'));
      await tester.pumpAndSettle();

      expect(
        find.byType(LicensePage),
        findsOneWidget,
        reason:
            'Acknowledgments must reach the framework license page, '
            "which renders the build's own dependency inventory rather "
            'than a hand-maintained list that goes stale',
      );
    });

    testWidgets('the license page carries the app name and version', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      // The action row scrolls: with eight buttons the last two sit below
      // the fold on the 800x600 test surface, and tapping an off-screen
      // finder silently hits nothing.
      await tester.ensureVisible(find.text('Acknowledgments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acknowledgments'));
      await tester.pumpAndSettle();

      expect(find.text('NetCrux'), findsWidgets);
      expect(find.text('1.2.3'), findsWidgets);
    });
  });
}
