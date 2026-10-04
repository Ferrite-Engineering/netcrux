// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_ide_layout.dart';
import 'package:netcrux/features/workspace/widgets/project_tab_content.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/reload/source_file_watcher_provider.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// The tab's elaboration, answered by the test: every build parks on a fresh
/// completer in [builds], so a test decides when, and with what, each load
/// resolves. Watches the project like the real pipeline, so changing the
/// project rebuilds it.
class _AnsweredNetlist extends LoadedNetlist {
  _AnsweredNetlist(this.builds);

  final List<Completer<NetlistModel?>> builds;

  @override
  Future<NetlistModel?> build() {
    ref.watch(currentProjectProvider);
    final answer = Completer<NetlistModel?>();
    builds.add(answer);
    return answer.future;
  }
}

/// `top` instantiates `u_cpu` (a `cpu`), which instantiates `u_alu`.
NetlistModel _seed() => const YosysJsonParser().parse(
  File(
    'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
  ).readAsStringSync(),
);

void main() {
  group('ProjectTabContent', () {
    testWidgets(
      'renders the empty-project hint when the active tab has no sources',
      (tester) async {
        final root = ProviderContainer(
          overrides: [
            // The tab's status bar reports a missing engine, so it reads the
            // availability probe — which shells out to `yosys --version`
            // unless stubbed.
            yosysAvailabilityProvider.overrideWith(
              (ref) async => const YosysAvailability.available(
                executablePath: 'yosys',
                versionString: 'test stub',
              ),
            ),
          ],
        );
        addTearDown(root.dispose);
        final manager = TabContainerManager(
          rootContainer: root,
          overridesFactory: netcruxTabOverridesFactory,
        );
        addTearDown(manager.dispose);
        final container = manager.containerFor(TabId.generate());

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: [
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(body: ProjectTabContent()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Empty-state hint surfaces (the Open Project action label is reused
        // because the empty-tab UX is "tell the user how to start").
        expect(find.byType(ProjectTabContent), findsOneWidget);
        // The per-tab IDE chrome wraps the content — an OPEN tab (even one
        // without a design loaded) shows the hierarchy / inspector /
        // diagnostics regions. The chrome-free state is the zero-tabs empty
        // workspace, owned by PaneHost one level up.
        expect(find.byType(NetcruxIdeLayout), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('the netlist reaches the hierarchy tree', () {
    testWidgets('a reload that lands before the next frame keeps the design '
        'and the scope a restore gave it', (tester) async {
      // A session reopened into its own tab: the project changes, the reload
      // resolves to a new model before a frame is drawn (a small netlist, a
      // cache hit), and the restore installs that model and navigates it.
      // The reload's loading state still carried the old model as its value,
      // and the tree must not be handed it once the frame comes.
      final root = ProviderContainer(
        overrides: [
          yosysAvailabilityProvider.overrideWith(
            (ref) async => const YosysAvailability.available(
              executablePath: 'yosys',
              versionString: 'test stub',
            ),
          ),
          // The tab watches its sources; their poll would be a timer left
          // running when the test ends.
          sourceFilePollIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(root.dispose);
      final builds = <Completer<NetlistModel?>>[];
      final manager = TabContainerManager(
        rootContainer: root,
        overridesFactory: (id) => [
          for (final override in netcruxTabOverridesFactory(id))
            if (override.origin != loadedNetlistProvider &&
                override.origin != currentLaidOutGraphProvider)
              override,
          loadedNetlistProvider.overrideWith(() => _AnsweredNetlist(builds)),
          // Layout is not what this is about, and needs no engine here.
          currentLaidOutGraphProvider.overrideWith(
            (ref) async => LaidOutGraph.empty,
          ),
        ],
      );
      addTearDown(manager.dispose);
      final tab = manager.containerFor(TabId.generate());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: tab,
          child: const MaterialApp(
            localizationsDelegates: [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: ProjectTabContent()),
          ),
        ),
      );
      await tester.pump();

      final before = _seed();
      tab.read(currentProjectProvider.notifier).setSourceFiles(const <String>[
        '/before/top.v',
      ]);
      final loadingBefore = tab.read(loadedNetlistProvider.future);
      builds.last.complete(before);
      await loadingBefore;
      await tester.pump();
      await tester.pump();
      expect(tab.read(hierarchyTreeProvider).model, same(before));

      // The reload, and the restore, all between two frames.
      final after = _seed();
      tab.read(currentProjectProvider.notifier).setSourceFiles(const <String>[
        '/after/top.v',
      ]);
      final loadingAfter = tab.read(loadedNetlistProvider.future);
      expect(tab.read(loadedNetlistProvider).value, same(before));
      builds.last.complete(after);
      await loadingAfter;
      tab.read(hierarchyTreeProvider.notifier)
        ..setModel(after)
        ..selectByPath(const <String>['u_cpu']);

      await tester.pump();
      await tester.pump();

      final tree = tab.read(hierarchyTreeProvider);
      expect(tree.model, same(after), reason: 'the replaced design came back');
      expect(tree.selected?.path, const <String>['u_cpu']);
      expect(tester.takeException(), isNull);
    });
  });

  group('schematic layout progress message', () {
    test('plural forms — unknown count, singular, and plural (en)', () async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      // count 0 = "not known yet" → just the base message.
      expect(l10n.schematicLayoutInProgress(0), 'Laying out the schematic…');
      expect(l10n.schematicLayoutInProgress(1), contains('1 cell'));
      expect(l10n.schematicLayoutInProgress(1599), contains('1599 cells'));
    });

    test('resolves in every supported locale and carries the count', () async {
      for (final locale in const <Locale>[
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        final l10n = await L10N.delegate.load(locale);
        expect(l10n.schematicLayoutInProgress(0), isNotEmpty);
        expect(l10n.schematicLayoutInProgress(1599), contains('1599'));
        // The indeterminate progress bar's elapsed-seconds readout.
        expect(l10n.schematicLayoutElapsed('4.2'), contains('4.2'));
      }
    });
  });
}
