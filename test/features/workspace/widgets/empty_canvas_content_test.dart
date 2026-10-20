// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/features/workspace/providers/recent_lists.dart';
import 'package:netcrux/features/workspace/widgets/empty_canvas_content.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// A Recent list's store, held in memory.
class _MemoryStore implements CruxRecentStore {
  _MemoryStore(this.entries);

  List<String> entries;

  @override
  Future<List<String>> load() async => entries;

  @override
  Future<void> save(List<String> next) async => entries = next;
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

typedef _Picker = Future<void> Function(String path);

Future<ProviderContainer> _pumpWith(
  WidgetTester tester, {
  required Locale locale,
  required EmptyCanvasContent child,
  List<String> projects = const <String>[],
  List<String> sources = const <String>[],
  List<String> workspaces = const <String>[],
  bool Function(String path)? exists,
  ApplicationBuildInfo? buildInfo,
}) async {
  final container = ProviderContainer(
    overrides: [
      recentProjects.storeProvider.overrideWithValue(_MemoryStore(projects)),
      recentSources.storeProvider.overrideWithValue(_MemoryStore(sources)),
      recentWorkspaces.storeProvider.overrideWithValue(
        _MemoryStore(workspaces),
      ),
      if (exists != null) ...[
        recentProjects.existsProvider.overrideWithValue(exists),
        recentSources.existsProvider.overrideWithValue(exists),
        recentWorkspaces.existsProvider.overrideWithValue(exists),
      ],
      if (buildInfo != null)
        aboutBuildInfoProvider.overrideWith((ref) async => buildInfo),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  // The header's GlowingAppIcon runs perpetual AnimationControllers
  // (.repeat), so pumpAndSettle never completes. Advance a bounded number of
  // frames instead — the same constraint WaveCrux's welcome test documents.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

EmptyCanvasContent _newContent({
  VoidCallback? onOpenProject,
  VoidCallback? onOpenSourceFiles,
  VoidCallback? onOpenWorkspace,
  _Picker? onPickRecentProject,
  _Picker? onPickRecentSourceFile,
  _Picker? onPickRecentWorkspace,
}) {
  return EmptyCanvasContent(
    onOpenProject: onOpenProject ?? () {},
    onOpenSourceFiles: onOpenSourceFiles ?? () {},
    onOpenWorkspace: onOpenWorkspace ?? () {},
    onPickRecentProject: onPickRecentProject ?? (_) async {},
    onPickRecentSourceFile: onPickRecentSourceFile ?? (_) async {},
    onPickRecentWorkspace: onPickRecentWorkspace ?? (_) async {},
  );
}

void main() {
  group('EmptyCanvasContent', () {
    testWidgets('renders the three primary Open actions + empty placeholders', (
      tester,
    ) async {
      await _pumpWith(
        tester,
        locale: const Locale('en'),
        child: _newContent(),
      );
      expect(find.text('Open Project…'), findsOneWidget);
      expect(find.text('Open Source Files…'), findsOneWidget);
      expect(find.text('Open Workspace…'), findsOneWidget);
      // Canonical (WaveCrux) welcome screen: Open actions + recents only,
      // no "New Tab" affordance.
      expect(find.text('New Tab'), findsNothing);
      // No recent files yet — the shared placeholder text appears.
      expect(find.text('No recent projects'), findsOneWidget);
      expect(find.text('No recent files'), findsOneWidget);
      // No Clear Recent button when there's nothing to clear, and no
      // workspaces section while that list is empty.
      expect(find.text('Clear Recent Projects'), findsNothing);
      expect(find.text('Recent workspaces'), findsNothing);
    });

    testWidgets('renders the version line under the subtitle', (tester) async {
      await _pumpWith(
        tester,
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
        locale: const Locale('en'),
        child: _newContent(),
      );
      expect(find.byKey(const Key('empty_canvas_version')), findsNothing);
    });

    testWidgets('lists every recent project / source / workspace', (
      tester,
    ) async {
      await _pumpWith(
        tester,
        locale: const Locale('en'),
        child: _newContent(),
        projects: const ['/d/cpu.netcrux-project'],
        sources: const ['/d/cpu.v', '/d/alu.sv'],
        workspaces: const ['/d/team.netcrux-workspace'],
        exists: (_) => true,
      );
      expect(find.text('cpu.netcrux-project'), findsOneWidget);
      expect(find.text('cpu.v'), findsOneWidget);
      expect(find.text('alu.sv'), findsOneWidget);
      expect(find.text('team.netcrux-workspace'), findsOneWidget);
      // A Clear Recent button per list, because each has entries.
      expect(find.text('Clear Recent Projects'), findsOneWidget);
      expect(find.text('Clear Recent Files'), findsOneWidget);
      expect(find.text('Clear Recent Workspaces'), findsOneWidget);
    });

    testWidgets('tapping a recent project fires onPickRecentProject', (
      tester,
    ) async {
      String? picked;
      await _pumpWith(
        tester,
        locale: const Locale('en'),
        child: _newContent(
          onPickRecentProject: (path) async => picked = path,
        ),
        projects: const ['/d/cpu.netcrux-project'],
        exists: (_) => true,
      );
      await tester.tap(find.text('cpu.netcrux-project'));
      await tester.pump();
      expect(picked, '/d/cpu.netcrux-project');
    });

    testWidgets('a row removes itself with its remove button', (tester) async {
      final container = await _pumpWith(
        tester,
        locale: const Locale('en'),
        child: _newContent(),
        projects: const ['/d/cpu.netcrux-project', '/d/alu.netcrux-project'],
        exists: (_) => true,
      );
      await tester.tap(find.byKey(const ValueKey('cruxRecentRemove')).first);
      await tester.pump();
      expect(container.read(recentProjects.provider), [
        '/d/alu.netcrux-project',
      ]);
      expect(find.text('cpu.netcrux-project'), findsNothing);
    });

    testWidgets('Clear Recent Projects empties the list and says so', (
      tester,
    ) async {
      final container = await _pumpWith(
        tester,
        locale: const Locale('en'),
        child: _newContent(),
        projects: const ['/d/cpu.netcrux-project'],
        exists: (_) => true,
      );
      await tester.tap(find.text('Clear Recent Projects'));
      await tester.pump();
      expect(container.read(recentProjects.provider), isEmpty);
      expect(find.text('Recent projects cleared.'), findsOneWidget);
      expect(find.text('No recent projects'), findsOneWidget);
    });

    testWidgets('a missing file is greyed, and opening it drops it', (
      tester,
    ) async {
      String? picked;
      final container = await _pumpWith(
        tester,
        locale: const Locale('en'),
        child: _newContent(
          onPickRecentProject: (path) async => picked = path,
        ),
        projects: const ['/d/gone.netcrux-project'],
        exists: (_) => false,
      );
      // The row names the problem instead of the path.
      expect(find.text('Project file not found'), findsOneWidget);

      await tester.tap(find.text('gone.netcrux-project'));
      await tester.pump();
      await tester.pump();

      expect(picked, isNull, reason: 'a missing file is never opened');
      expect(container.read(recentProjects.provider), isEmpty);
      expect(
        find.text(
          'gone.netcrux-project could not be opened and was removed from '
          'Recent Projects.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('locale sweep — zh_CN', (tester) async {
      await _pumpWith(
        tester,
        locale: const Locale('zh', 'CN'),
        child: _newContent(),
      );
      expect(find.text('欢迎使用 NetCrux'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locale sweep — ja', (tester) async {
      await _pumpWith(
        tester,
        locale: const Locale('ja'),
        child: _newContent(),
      );
      expect(find.text('NetCrux へようこそ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locale sweep — ko', (tester) async {
      await _pumpWith(
        tester,
        locale: const Locale('ko'),
        child: _newContent(),
      );
      expect(find.text('NetCrux에 오신 것을 환영합니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
