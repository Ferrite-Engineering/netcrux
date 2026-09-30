// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/domain/enums/yosys_path_mode.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/workspace/widgets/empty_canvas_content.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

class _SettingsHarness extends AppSettingsNotifier {
  _SettingsHarness(this.initial);

  final AppSettings initial;

  @override
  Future<AppSettings> build() async => initial;
}

/// Fixed build metadata for the version-line test, so the assertion does not
/// track the real `pubspec.yaml` version.
const _testBuildInfo = ApplicationBuildInfo(
  version: '9.9.9',
  buildNumber: '7',
  gitShortSha: 'abc1234',
  os: 'macos',
  architecture: 'arm64',
  flutterSdkVersion: '3.44.8',
  dartSdkVersion: '3.12.2',
);

Future<void> _pumpWith(
  WidgetTester tester, {
  required AppSettings settings,
  required Locale locale,
  required EmptyCanvasContent child,
  ApplicationBuildInfo? buildInfo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsProvider.overrideWith(() => _SettingsHarness(settings)),
        if (buildInfo != null)
          aboutBuildInfoProvider.overrideWith((ref) async => buildInfo),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  // The header's GlowingAppIcon runs perpetual AnimationControllers
  // (.repeat), so pumpAndSettle never completes. Advance a bounded number of
  // frames instead — the same constraint WaveCrux's welcome test documents.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

EmptyCanvasContent _newContent({
  VoidCallback? onOpenProject,
  VoidCallback? onOpenSourceFiles,
  VoidCallback? onOpenWorkspace,
  ValueChanged<String>? onPickRecentProject,
  ValueChanged<String>? onPickRecentSourceFile,
  ValueChanged<String>? onPickRecentWorkspace,
  VoidCallback? onClearRecent,
}) {
  return EmptyCanvasContent(
    onOpenProject: onOpenProject ?? () {},
    onOpenSourceFiles: onOpenSourceFiles ?? () {},
    onOpenWorkspace: onOpenWorkspace ?? () {},
    onPickRecentProject: onPickRecentProject ?? (_) {},
    onPickRecentSourceFile: onPickRecentSourceFile ?? (_) {},
    onPickRecentWorkspace: onPickRecentWorkspace ?? (_) {},
    onClearRecent: onClearRecent ?? () {},
  );
}

void main() {
  group('EmptyCanvasContent', () {
    testWidgets('renders the three primary Open actions + empty placeholders', (
      tester,
    ) async {
      await _pumpWith(
        tester,
        settings: const AppSettings.defaults(),
        locale: const Locale('en'),
        child: _newContent(),
      );
      expect(find.text('Open Project…'), findsOneWidget);
      expect(find.text('Open Source Files…'), findsOneWidget);
      expect(find.text('Open Workspace…'), findsOneWidget);
      // Canonical (WaveCrux) welcome screen: Open actions + recents only,
      // no "New Tab" affordance.
      expect(find.text('New Tab'), findsNothing);
      // No recent files yet — placeholder text appears.
      expect(find.text('No recent projects yet.'), findsOneWidget);
      expect(find.text('No recent source files yet.'), findsOneWidget);
      // No "Clear recent" button when there's nothing to clear.
      expect(find.text('Clear recent'), findsNothing);
    });

    testWidgets('renders the version line under the subtitle', (tester) async {
      await _pumpWith(
        tester,
        settings: const AppSettings.defaults(),
        locale: const Locale('en'),
        child: _newContent(),
        buildInfo: _testBuildInfo,
      );
      final versionText = find.byKey(const Key('empty_canvas_version'));
      expect(versionText, findsOneWidget);
      expect(tester.widget<Text>(versionText).data, 'Version 9.9.9');
    });

    testWidgets('omits the version line until build info resolves', (
      tester,
    ) async {
      // No aboutBuildInfoProvider override: the real provider is async, so on
      // the first frames `.value` is null and nothing should render.
      await _pumpWith(
        tester,
        settings: const AppSettings.defaults(),
        locale: const Locale('en'),
        child: _newContent(),
      );
      expect(find.byKey(const Key('empty_canvas_version')), findsNothing);
    });

    testWidgets('lists every recent project / source / workspace', (
      tester,
    ) async {
      const settings = AppSettings(
        core: CoreSettings.defaults(),
        recentProjectPaths: ['/d/cpu.netcrux-project'],
        recentSourceFilePaths: ['/d/cpu.v', '/d/alu.sv'],
        recentWorkspacePaths: ['/d/team.netcrux-workspace'],
        yosysPathMode: YosysPathMode.autoDetect,
        yosysCustomPath: '',
      );
      await _pumpWith(
        tester,
        settings: settings,
        locale: const Locale('en'),
        child: _newContent(),
      );
      expect(find.text('cpu.netcrux-project'), findsOneWidget);
      expect(find.text('cpu.v'), findsOneWidget);
      expect(find.text('alu.sv'), findsOneWidget);
      expect(find.text('team.netcrux-workspace'), findsOneWidget);
      // Clear button surfaces because there are recent entries.
      expect(find.text('Clear recent'), findsOneWidget);
    });

    testWidgets('tapping a recent project fires onPickRecentProject', (
      tester,
    ) async {
      const settings = AppSettings(
        core: CoreSettings.defaults(),
        recentProjectPaths: ['/d/cpu.netcrux-project'],
        recentSourceFilePaths: <String>[],
        recentWorkspacePaths: <String>[],
        yosysPathMode: YosysPathMode.autoDetect,
        yosysCustomPath: '',
      );
      String? picked;
      await _pumpWith(
        tester,
        settings: settings,
        locale: const Locale('en'),
        child: _newContent(onPickRecentProject: (path) => picked = path),
      );
      await tester.tap(find.text('cpu.netcrux-project'));
      expect(picked, '/d/cpu.netcrux-project');
    });

    testWidgets('locale sweep — zh_CN', (tester) async {
      await _pumpWith(
        tester,
        settings: const AppSettings.defaults(),
        locale: const Locale('zh', 'CN'),
        child: _newContent(),
      );
      expect(find.text('欢迎使用 NetCrux'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locale sweep — ja', (tester) async {
      await _pumpWith(
        tester,
        settings: const AppSettings.defaults(),
        locale: const Locale('ja'),
        child: _newContent(),
      );
      expect(find.text('NetCrux へようこそ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locale sweep — ko', (tester) async {
      await _pumpWith(
        tester,
        settings: const AppSettings.defaults(),
        locale: const Locale('ko'),
        child: _newContent(),
      );
      expect(find.text('NetCrux에 오신 것을 환영합니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
