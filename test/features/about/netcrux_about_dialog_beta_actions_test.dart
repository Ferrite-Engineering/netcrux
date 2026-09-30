// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/core/updates/netcrux_update_config.dart';
import 'package:netcrux/features/about/netcrux_about_dialog.dart';
import 'package:netcrux/features/issue_reporter/netcrux_issue_reporter_overrides.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';

/// The two beta actions the About box carries — "Check for Updates"
/// and "Submit Issue…" — plus the beta indicator chip. Both reuse the action
/// labels, so the suite-wide ellipsis rule applies: the update check runs
/// immediately (no ellipsis), the issue reporter opens a dialog first.
///
/// The About box is where a user already goes to find their version and build
/// SHA, which are the two things every bug report needs, so it is the natural
/// second home for both actions alongside the Help menu and the palette.
class _RecordingStatus extends UpdateStatusNotifier {
  int manualChecks = 0;

  @override
  UpdateStatus build() => const UpdateStatusCurrent();

  @override
  Future<void> checkNow() async => manualChecks++;
}

const _stubBuildInfo = ApplicationBuildInfo(
  version: '1.2.3',
  buildNumber: '42',
  gitShortSha: 'abc1234',
  os: 'macOS 15.0',
  architecture: 'arm64',
  flutterSdkVersion: '3.29.0',
  dartSdkVersion: '3.7.0',
);

void main() {
  late _RecordingStatus status;

  setUp(() => status = _RecordingStatus());

  Widget buildApp({String locale = 'en', bool? betaPeriod}) => ProviderScope(
    overrides: <Override>[
      aboutBuildInfoProvider.overrideWith((_) async => _stubBuildInfo),
      cruxUpdateConfigProvider.overrideWithValue(netcruxUpdateConfig),
      updateStatusProvider.overrideWith(() => status),
      ...netcruxIssueReporterOverrides,
      // Opening the reporter builds the session snapshot, which reads the
      // Yosys availability probe — a real subprocess without this stub.
      yosysAvailabilityProvider.overrideWith(
        (_) async => const YosysAvailability.notFound(),
      ),
      if (betaPeriod != null) betaPeriodProvider.overrideWithValue(betaPeriod),
    ],
    child: MaterialApp(
      locale: Locale(locale),
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

  Future<void> openDialog(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.tap(find.text('open-about'));
    await tester.pump(); // run the handler up to the build-info await
    await tester.pump(); // resolve the build-info future microtask
    // The route transition must finish before the action row is hit-testable
    // (it sits behind an IgnorePointer while the dialog fades in). The About
    // box has no perpetual animation, so settling terminates.
    await tester.pumpAndSettle();
  }

  testWidgets('both beta actions are present', (tester) async {
    await tester.pumpWidget(buildApp());
    await openDialog(tester);

    expect(find.text('Check for Updates'), findsOneWidget);
    expect(find.text('Submit Issue…'), findsOneWidget);
  });

  testWidgets('Check for Updates runs a manual check', (tester) async {
    await tester.pumpWidget(buildApp());
    await openDialog(tester);

    final button = find.widgetWithText(OutlinedButton, 'Check for Updates');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();

    // A manual check ignores the Settings → General auto-check toggle, which
    // is exactly why the About-box button exists.
    expect(status.manualChecks, 1);
  });

  testWidgets('Submit Issue opens the reporter', (tester) async {
    await tester.pumpWidget(buildApp());
    await openDialog(tester);

    final button = find.widgetWithText(OutlinedButton, 'Submit Issue…');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(CruxIssueReporterDialog), findsOneWidget);

    // Close the reporter before the test ends: its summary field owns a
    // cursor-blink timer, and flutter_test asserts no timer outlives the tree.
    Navigator.of(
      tester.element(find.byType(CruxIssueReporterDialog)),
    ).pop();
    await tester.pumpAndSettle();
  });

  group('beta indicator chip', () {
    testWidgets('is shown while the beta period is on', (tester) async {
      await tester.pumpWidget(buildApp(betaPeriod: true));
      await openDialog(tester);
      // The chip is rendered by the shared crux_about_dialog surface from
      // `betaPeriodProvider`; NetCrux ships it by consuming that surface.
      expect(find.textContaining('Beta'), findsWidgets);
    });

    testWidgets('is absent post-beta', (tester) async {
      await tester.pumpWidget(buildApp(betaPeriod: false));
      await openDialog(tester);
      expect(find.textContaining('Public Beta'), findsNothing);
    });
  });

  group('locale sweep', () {
    for (final locale in ['en', 'zh_CN', 'ja', 'ko']) {
      testWidgets('both actions render in $locale', (tester) async {
        await tester.pumpWidget(buildApp(locale: locale));
        await openDialog(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
