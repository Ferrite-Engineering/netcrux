import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/annotations/services/annotation_actions.dart';
import 'package:netcrux/features/annotations/widgets/annotations_panel.dart';
import 'package:netcrux/features/annotations/widgets/inline_element_picker.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/annotation_state.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';
import 'package:netcrux/services/session/in_session_annotation_store.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';
import 'package:netcrux/shared/widgets/netcrux_feature_tier_badge.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';

import '../../../helpers/telemetry_test_overrides.dart';

const List<Locale> _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

Future<(BuildContext, WidgetRef)> _pumpHost(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  late BuildContext ctx;
  late WidgetRef wref;
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...netcruxTelemetryTestOverrides(),
        annotationStoreProvider.overrideWith(
          InSessionAnnotationStore.new,
        ),
        annotationSnapshotProvider.overrideWith(
          (ref) => ref.watch(annotationStateProvider),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const <LocalizationsDelegate<Object?>>[
          L10N.delegate,
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: _locales,
        home: Consumer(
          builder: (context, ref, _) {
            wref = ref;
            return Scaffold(
              body: Builder(
                builder: (innerContext) {
                  ctx = innerContext;
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (ctx, wref);
}

const AnnotationTarget _dmaReg = AnnotationTarget(
  kind: AnnotationTargetKind.cell,
  targetId: 'dma_reg',
);

/// `top` instantiates `u_cpu` (a `cpu`) and has a `dma_reg` cell.
NetlistModel _seedModel() => const YosysJsonParser().parse(
  File(
    'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
  ).readAsStringSync(),
);

const AnnotationTarget _target = AnnotationTarget(
  kind: AnnotationTargetKind.cell,
  targetId: 'top.alu',
);

/// Pumps the production workspace topology (an in-memory workspace with
/// one open tab, a real [TabContainerManager], and a
/// [WorkspaceManagersScope]) and returns the mounted context/ref plus the
/// active tab's container. The command-palette opener path resolves the
/// active tab's container through this scope, so the harness must supply
/// it; the returned container is where a test seeds the active selection.
Future<(BuildContext, WidgetRef, ProviderContainer)> _pumpWorkspaceHost(
  WidgetTester tester,
) async {
  late BuildContext ctx;
  late WidgetRef wref;
  final root = ProviderContainer(
    overrides: <Override>[
      ...netcruxTelemetryTestOverrides(),
      annotationStoreProvider.overrideWith(
        InSessionAnnotationStore.new,
      ),
      annotationSnapshotProvider.overrideWith(
        (ref) => ref.watch(annotationStateProvider),
      ),
      netcruxWorkspaceProvider.overrideWith(
        () => NetcruxWorkspaceNotifier(
          service: WorkspaceService<NetcruxTabPayload>(
            codec: const NetcruxWorkspaceCodec(),
            directoryFactory: () async =>
                Directory.systemTemp.createTempSync('netcrux_annotation_host_'),
            logger: (_) {},
          ),
          autoSaveDebounce: const Duration(milliseconds: 50),
          // Fake-async zone: the settings-backed launch gate reads a
          // platform channel whose reply never arrives before the first
          // pump, and this harness awaits the workspace future first.
          restoreGate: () async => true,
        ),
      ),
    ],
  );
  addTearDown(root.dispose);
  final tabs = TabContainerManager(
    rootContainer: root,
    overridesFactory: netcruxTabOverridesFactory,
  );
  addTearDown(tabs.dispose);
  final panes = PaneContainerManager(
    rootContainer: root,
    overridesFactory: netcruxPaneOverridesFactory,
  );
  addTearDown(panes.dispose);
  await root.read(netcruxWorkspaceProvider.future);
  await root
      .read(netcruxWorkspaceProvider.notifier)
      .openTab(
        displayName: 'annotation host',
        payload: NetcruxTabPayload.empty,
      );
  final activeTabId = root.read(netcruxWorkspaceProvider).value!.activeTabId!;
  final tabContainer = tabs.containerFor(activeTabId);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: root,
      child: WorkspaceManagersScope(
        tabContainerManager: tabs,
        paneContainerManager: panes,
        child: MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<Object?>>[
            L10N.delegate,
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: _locales,
          home: Consumer(
            builder: (context, ref, _) {
              wref = ref;
              return Scaffold(
                body: Builder(
                  builder: (innerContext) {
                    ctx = innerContext;
                    return const SizedBox.shrink();
                  },
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (ctx, wref, tabContainer);
}

void main() {
  group('openAnnotationsPanel', () {
    // Full dock behaviour (focus, toggle, the tab's x) is covered by
    // test/features/annotations/annotation_dock_test.dart; this pins that the
    // opener docks instead of pushing a dialog route.
    testWidgets('docks its tab and opens no dialog', (tester) async {
      final (ctx, _) = await _pumpHost(tester);
      openAnnotationsPanel(ctx);
      await tester.pumpAndSettle();
      final root = ProviderScope.containerOf(ctx, listen: false);
      expect(root.read(analysisDockProvider), <AnalysisPanelKind>[
        AnalysisPanelKind.annotations,
      ]);
      expect(
        root.read(rightDockTabProvider),
        analysisDockTabId(AnalysisPanelKind.annotations),
      );
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AnnotationsPanel), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('openAddAnnotationDialog', () {
    testWidgets('an explicit target opens the annotation dialog', (
      tester,
    ) async {
      final (ctx, ref) = await _pumpHost(tester);
      openAddAnnotationDialog(ctx, ref, target: _target);
      await tester.pumpAndSettle();
      expect(find.byType(NetCruxFeatureTierBadge), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(
          L10N
              .of(tester.element(find.byType(AlertDialog)))
              .annotationDialogTitle,
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'no target resolves the ACTIVE TAB selection, not the root container',
      (tester) async {
        final (ctx, ref, tabContainer) = await _pumpWorkspaceHost(tester);
        // Seed the active tab's selection; the root container stays empty.
        // Reading the root ref's (empty) selection would fall through to the
        // inline element picker.
        tabContainer
            .read(selectedElementProvider.notifier)
            .select(const SelectedElement.cell(cellId: 'top.alu'));

        openAddAnnotationDialog(ctx, ref);
        await tester.pumpAndSettle();

        // The annotation dialog opened for the resolved selection; the
        // inline picker fallback never appeared.
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(NetCruxFeatureTierBadge), findsNothing);
        expect(find.byType(InlineElementPicker), findsNothing);
      },
    );

    testWidgets(
      'no target with no active selection falls back to the inline picker '
      'scoped to the active tab',
      (tester) async {
        final (ctx, ref, _) = await _pumpWorkspaceHost(tester);
        // No selection seeded — the opener falls back to the inline picker,
        // which mounts inside the active tab's provider scope.
        openAddAnnotationDialog(ctx, ref);
        await tester.pumpAndSettle();

        expect(find.byType(InlineElementPicker), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a titled annotation added from the palette lands in the ACTIVE TAB '
      'store, with the module of the scope on screen',
      (tester) async {
        final (ctx, ref, tabContainer) = await _pumpWorkspaceHost(tester);
        tabContainer
            .read(hierarchyTreeProvider.notifier)
            .setModel(_seedModel());
        openAddAnnotationDialog(ctx, ref, target: _dmaReg);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('annotationDialogTitleField')),
          'PC',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final inTab = tabContainer.read(annotationSnapshotProvider).annotations;
        expect(inTab.single.title, 'PC');
        expect(inTab.single.body, isEmpty);
        expect(inTab.single.moduleName, 'top');
        final root = ProviderScope.containerOf(ctx, listen: false);
        expect(root.read(annotationSnapshotProvider).annotations, isEmpty);
      },
    );

    testWidgets(
      'an annotation body added from the palette lands in the ACTIVE TAB store',
      (tester) async {
        final (ctx, ref, tabContainer) = await _pumpWorkspaceHost(tester);
        openAddAnnotationDialog(ctx, ref, target: _dmaReg);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('annotationDialogBodyField')),
          'Resets late',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final inTab = tabContainer.read(annotationSnapshotProvider).annotations;
        expect(inTab.single.title, isNull);
        expect(inTab.single.body, 'Resets late');
        final root = ProviderScope.containerOf(ctx, listen: false);
        expect(root.read(annotationSnapshotProvider).annotations, isEmpty);
      },
    );
  });

  group('mapSelectionToAnnotationTarget', () {
    test('maps a cell selection to a cell target', () {
      final target = mapSelectionToAnnotationTarget(
        const SelectedElement.cell(cellId: 'top.alu'),
      );
      expect(target?.kind, AnnotationTargetKind.cell);
      expect(target?.targetId, 'top.alu');
    });

    test('maps a wire selection to a net target', () {
      final target = mapSelectionToAnnotationTarget(
        const SelectedElement.wire(edgeId: 'e0', netId: 4),
      );
      expect(target?.kind, AnnotationTargetKind.net);
      expect(target?.targetId, 'e0');
    });

    test('maps the none sentinel to null', () {
      expect(
        mapSelectionToAnnotationTarget(const SelectedElement.none()),
        isNull,
      );
    });
  });
}
