// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_ide_layout/crux_ide_layout.dart';
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
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';
import 'package:netcrux/services/reload/source_file_watcher_provider.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

import '../../../helpers/cxp_test_overrides.dart';

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

/// One AND gate between three ports: the module the progress test lays out.
const _and2Json = <String, Object?>{
  'creator': 'Yosys test',
  'modules': <String, Object?>{
    'and2': <String, Object?>{
      'attributes': <String, Object?>{'top': '1'},
      'ports': <String, Object?>{
        'a': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[2],
        },
        'y': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[3],
        },
      },
      'cells': <String, Object?>{
        'u_and': <String, Object?>{
          'hide_name': 0,
          'type': r'$and',
          'parameters': <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': <String, Object?>{'A': 'input', 'Y': 'output'},
          'connections': <String, Object?>{
            'A': <Object>[2],
            'Y': <Object>[3],
          },
        },
      },
      'netnames': <String, Object?>{},
    },
  },
};

/// A solver whose jobs sit in crossing minimization, 40 % through, until
/// they are cancelled; counts the cancels.
class _EndlessJobSolver implements ElkJobSolver {
  int cancels = 0;

  @override
  String get engineDescription => 'endless jobs';

  @override
  String solve(String inputJson) => throw UnimplementedError();

  @override
  ElkSolveJob start(String inputJson) => _EndlessJob(this);

  @override
  void dispose() {}
}

class _EndlessJob implements ElkSolveJob {
  _EndlessJob(this._solver);

  final _EndlessJobSolver _solver;
  bool _cancelled = false;

  @override
  ({bool done, LayoutProgress? progress}) poll() => (
    done: _cancelled,
    progress: const LayoutProgress(
      phase: LayoutPhase.crossingMinimization,
      fraction: 0.4,
    ),
  );

  @override
  void cancel() {
    if (!_cancelled) _solver.cancels++;
    _cancelled = true;
  }

  @override
  String finish() => throw const LayoutCancelledException();
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

  group('the source-changed prompt', () {
    testWidgets('is the shared banner, and Ignore closes it without a reload', (
      tester,
    ) async {
      final root = ProviderContainer(
        overrides: [
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

      // It used to be a snackbar whose only button was Reload, which never
      // timed out and could not be declined.
      container.read(sourceReloadEventsProvider.notifier).publish(1);
      await tester.pumpAndSettle();
      expect(find.byKey(kCruxReloadPromptKey), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      // A second change while it is up does not stack another banner.
      container.read(sourceReloadEventsProvider.notifier).publish(2);
      await tester.pumpAndSettle();
      expect(find.byKey(kCruxReloadPromptKey), findsOneWidget);

      await tester.tap(find.byKey(kCruxReloadPromptIgnoreKey));
      await tester.pumpAndSettle();
      expect(find.byKey(kCruxReloadPromptKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
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
          // Opening a design reads whether the CXP server runs.
          ...netcruxCxpOffTestOverrides(),
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

  group('layout progress and Cancel', () {
    testWidgets('the bar follows the engine, Cancel stops the solve, and Lay '
        'out again starts it over', (tester) async {
      final solver = _EndlessJobSolver();
      final service = ElkLayoutService(
        solverFactory: () => solver,
        assetLoader: (_) async => throw StateError('elkjs must not load'),
      );
      final module = NetlistModel.fromJson(_and2Json).modules['and2']!;
      var layouts = 0;
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
          elkLayoutServiceProvider.overrideWithValue(service),
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
          // The real provider's solve path, without the graph around it.
          currentLaidOutGraphProvider.overrideWith((ref) async {
            final layoutService = ref.read(elkLayoutServiceProvider);
            ref.onDispose(layoutService.cancelInFlightLayout);
            layouts++;
            await layoutService.layout(module);
            return LaidOutGraph.empty;
          }),
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
      tab.read(currentProjectProvider.notifier).setSourceFiles(const <String>[
        '/design/top.v',
      ]);
      final loading = tab.read(loadedNetlistProvider.future);
      builds.last.complete(_seed());
      await loading;

      Future<void> runFor(Duration time) async {
        const step = Duration(milliseconds: 50);
        for (var t = Duration.zero; t < time; t += step) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await runFor(const Duration(milliseconds: 500));
      expect(layouts, 1);
      expect(find.textContaining('Reducing wire crossings'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.4);

      await tester.tap(find.text('Cancel'));
      await runFor(const Duration(milliseconds: 200));
      expect(solver.cancels, 1);
      expect(find.text('Layout stopped.'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.tap(find.text('Lay out again'));
      await runFor(const Duration(milliseconds: 500));
      expect(layouts, 2);
      expect(find.textContaining('Reducing wire crossings'), findsOneWidget);

      // End stopped, so no solve or ticker outlives the test.
      await tester.tap(find.text('Cancel'));
      await runFor(const Duration(milliseconds: 200));
      expect(solver.cancels, 2);
      expect(find.text('Layout stopped.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('every phase has a label in every supported locale', () async {
      for (final locale in const <Locale>[
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        final l10n = await L10N.delegate.load(locale);
        final labels = <String>{
          for (final phase in LayoutPhase.values) layoutPhaseLabel(l10n, phase),
        };
        expect(labels, hasLength(LayoutPhase.values.length), reason: '$locale');
        expect(labels.every((l) => l.isNotEmpty), isTrue);
        expect(l10n.schematicLayoutStopped, isNotEmpty);
        expect(l10n.schematicLayoutRetry, isNotEmpty);
      }
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
