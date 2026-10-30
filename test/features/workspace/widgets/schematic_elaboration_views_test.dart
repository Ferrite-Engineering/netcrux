// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/statistics/providers/elaboration_progress_provider.dart';
import 'package:netcrux/features/workspace/widgets/project_tab_content.dart';
import 'package:netcrux/features/workspace/widgets/schematic_elaboration_progress_view.dart';
import 'package:netcrux/features/workspace/widgets/schematic_elaboration_stopped_view.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/reload/source_file_watcher_provider.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';

import '../../../helpers/cxp_test_overrides.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

/// An elaboration that parks until it is cancelled, as Yosys does.
class _ParkedNetlist extends LoadedNetlist {
  static int builds = 0;
  static int cancels = 0;
  Completer<NetlistModel?>? _parked;

  @override
  Future<NetlistModel?> build() {
    ref.watch(currentProjectProvider);
    builds++;
    final parked = _parked = Completer<NetlistModel?>();
    ref.onDispose(() {
      if (!parked.isCompleted) parked.complete(null);
    });
    return parked.future;
  }

  @override
  void cancelElaboration() {
    cancels++;
    final parked = _parked;
    if (parked != null && !parked.isCompleted) parked.complete(null);
  }
}

Future<ProviderContainer> _pumpTab(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  _ParkedNetlist.builds = 0;
  _ParkedNetlist.cancels = 0;
  final root = ProviderContainer(
    overrides: [
      ...netcruxCxpOffTestOverrides(),
      yosysAvailabilityProvider.overrideWith(
        (ref) async => const YosysAvailability.available(
          executablePath: 'yosys',
          versionString: 'test stub',
        ),
      ),
      sourceFilePollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(root.dispose);
  final manager = TabContainerManager(
    rootContainer: root,
    overridesFactory: (id) => [
      for (final override in netcruxTabOverridesFactory(id))
        if (override.origin != loadedNetlistProvider) override,
      loadedNetlistProvider.overrideWith(_ParkedNetlist.new),
    ],
  );
  addTearDown(manager.dispose);
  final tab = manager.containerFor(TabId.generate());
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: tab,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(body: ProjectTabContent()),
      ),
    ),
  );
  tab.read(currentProjectProvider.notifier).setSourceFiles(const <String>[
    '/design/top.v',
  ]);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return tab;
}

void main() {
  testWidgets('an elaboration shows what is running with the Yosys pass and '
      'Cancel, and Cancel leaves a way to start again', (tester) async {
    final tab = await _pumpTab(tester);

    expect(find.text('Elaborating the design…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('s elapsed'), findsOneWidget);

    tab
        .read(elaborationProgressProvider.notifier)
        .consumeStderrLine(
          '4. Executing HIERARCHY pass (managing design hierarchy).',
        );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('HIERARCHY'), findsOneWidget);

    await tester.tap(find.byKey(SchematicElaborationProgressView.cancelKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_ParkedNetlist.cancels, 1);
    expect(find.text('Elaboration stopped.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    final buildsBefore = _ParkedNetlist.builds;
    await tester.tap(find.byKey(SchematicElaborationStoppedView.retryKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_ParkedNetlist.builds, buildsBefore + 1);
    expect(find.text('Elaborating the design…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pre-built netlist says it is being read', (tester) async {
    final tab = await _pumpTab(tester);
    tab.read(currentProjectProvider.notifier).setSourceFiles(const <String>[
      '/design/top.json',
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reading the netlist…'), findsOneWidget);
  });

  for (final locale in _locales) {
    final tag = locale.countryCode == null
        ? locale.languageCode
        : '${locale.languageCode}_${locale.countryCode}';
    testWidgets('[$tag] the progress and stopped views are localized', (
      tester,
    ) async {
      final l10n = await L10N.delegate.load(locale);
      await _pumpTab(tester, locale: locale);
      expect(find.text(l10n.schematicElaborationInProgress), findsOneWidget);
      expect(find.text(l10n.commonCancel), findsOneWidget);

      await tester.tap(find.byKey(SchematicElaborationProgressView.cancelKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(l10n.schematicElaborationStopped), findsOneWidget);
      expect(find.text(l10n.schematicElaborationRetry), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
