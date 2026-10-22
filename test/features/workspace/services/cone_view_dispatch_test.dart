// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The cone view through the action dispatcher, at every tier. The
// depth-limited form is open core and runs at Open Core after the beta with
// no Pro overlay; the unlimited form is Pro, denied at Open Core after the
// beta, admitted at Pro and Enterprise, and a build with no walk for it says
// it requires NetCrux Pro.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/interfaces/transitive_cone_resolver.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/workspace/services/workspace_action_dispatcher.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';
import 'package:netcrux/services/schematic/transitive_cone_resolver_provider.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';

import '../../../helpers/telemetry_test_overrides.dart';

class _NoopResolver implements TransitiveConeResolver {
  @override
  Future<TraceOverlay> resolve(
    SchematicGraph graph,
    SelectedElement root,
    ConeOfInfluenceMode mode,
  ) async => TraceOverlay.empty;
}

typedef _Rig = ({
  WorkspaceActionDispatcher dispatcher,
  BuildContext context,
  ProviderContainer tab,
});

Future<_Rig> _pump(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
}) async {
  final root = ProviderContainer(
    overrides: <Override>[
      ...netcruxTelemetryTestOverrides(),
      cruxCxpProductBindingProvider.overrideWithValue(kNetcruxCxpBinding),
      cruxCxpTransportAvailableProvider.overrideWithValue(false),
      netcruxWorkspaceProvider.overrideWith(
        () => NetcruxWorkspaceNotifier(
          service: WorkspaceService<NetcruxTabPayload>(
            codec: const NetcruxWorkspaceCodec(),
            directoryFactory: () async =>
                Directory.systemTemp.createTempSync('nc_cone_dispatch_'),
            logger: (_) {},
          ),
          autoSaveDebounce: Duration.zero,
          restoreGate: () async => true,
        ),
      ),
      ...overrides,
    ],
  );
  addTearDown(() => tester.pump(const Duration(seconds: 10)));
  final tabs = TabContainerManager(
    rootContainer: root,
    overridesFactory: netcruxTabOverridesFactory,
  );
  final panes = PaneContainerManager(
    rootContainer: root,
    overridesFactory: netcruxPaneOverridesFactory,
  );
  addTearDown(() {
    tabs.dispose();
    panes.dispose();
    root.dispose();
  });
  await root.read(netcruxWorkspaceProvider.future);
  await root
      .read(netcruxWorkspaceProvider.notifier)
      .openTab(
        displayName: 'large_chain',
        payload: const NetcruxTabPayload(
          sourceFiles: <String>[],
          topModule: 'large_chain',
        ),
      );
  final tab = tabs.containerFor(
    root.read(netcruxWorkspaceProvider).value!.activeTabId!,
  );
  final model = NetlistModel.fromJson(
    jsonDecode(
          File(
            'test/fixtures/verilog/large_chain.expected.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>,
  );
  tab.read(hierarchyTreeProvider.notifier).setModel(model);
  final sub = tab.listen<ConeViewRequest?>(
    coneViewProvider,
    (previous, next) {},
  );
  addTearDown(sub.close);

  late WorkspaceActionDispatcher dispatcher;
  late BuildContext hostContext;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: root,
      child: WorkspaceManagersScope(
        tabContainerManager: tabs,
        paneContainerManager: panes,
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                hostContext = context;
                dispatcher = WorkspaceActionDispatcher(
                  ref: ref,
                  openProject: () async {},
                  openSourceFiles: () async {},
                  openNetlistJson: () async {},
                  openWorkspaceFlow: () async {},
                  openDesignByPath: (_) async {},
                );
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (dispatcher: dispatcher, context: hostContext, tab: tab);
}

void _select(ProviderContainer tab, String cellId) => tab
    .read(selectedElementProvider.notifier)
    .select(SelectedElement.cell(cellId: cellId));

void main() {
  group('Cone View, open core', () {
    testWidgets('runs at Open Core after the beta with no overlay', (
      tester,
    ) async {
      final rig = await _pump(
        tester,
        overrides: <Override>[
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
          proOverlayInstalledProvider.overrideWithValue(false),
        ],
      );
      _select(rig.tab, 'u_inv_7');
      rig.dispatcher.dispatch(rig.context, NetcruxAction.showConeView);
      await tester.pump();

      final shown = rig.tab.read(coneViewProvider);
      expect(shown?.root, const SelectedElement.cell(cellId: 'u_inv_7'));
      expect(shown?.isTransitive, isFalse);
      expect(find.byType(CruxUpgradeDialog), findsNothing);
      expect(tester.takeException(), isNull);

      rig.dispatcher.dispatch(rig.context, NetcruxAction.exitConeView);
      await tester.pump();
      expect(rig.tab.read(coneViewProvider), isNull);
      // Leaving reads the tab's layout to frame the root, which starts the
      // tab's pipeline; let it finish.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('with nothing selected it does nothing', (tester) async {
      final rig = await _pump(tester);
      rig.dispatcher.dispatch(rig.context, NetcruxAction.showConeView);
      await tester.pump();
      expect(rig.tab.read(coneViewProvider), isNull);
    });
  });

  group('Cone View, All Levels', () {
    testWidgets('is denied at Open Core after the beta', (tester) async {
      final rig = await _pump(
        tester,
        overrides: <Override>[
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
          proOverlayInstalledProvider.overrideWithValue(true),
          transitiveConeResolverProvider.overrideWithValue(_NoopResolver()),
        ],
      );
      _select(rig.tab, 'u_inv_7');
      rig.dispatcher.dispatch(
        rig.context,
        NetcruxAction.showConeViewAllLevels,
      );
      await tester.pumpAndSettle();
      expect(rig.tab.read(coneViewProvider), isNull);
      expect(find.byType(CruxUpgradeDialog), findsOneWidget);
    });

    for (final tier in const <LicenseTier>[
      LicenseTier.pro,
      LicenseTier.enterprise,
    ]) {
      testWidgets('is admitted at ${tier.name} after the beta', (tester) async {
        final rig = await _pump(
          tester,
          overrides: <Override>[
            betaPeriodProvider.overrideWithValue(false),
            licenseTierProvider.overrideWith((_) => tier),
            proOverlayInstalledProvider.overrideWithValue(true),
            transitiveConeResolverProvider.overrideWithValue(_NoopResolver()),
          ],
        );
        _select(rig.tab, 'u_inv_7');
        rig.dispatcher.dispatch(
          rig.context,
          NetcruxAction.showConeViewAllLevels,
        );
        await tester.pump();
        final shown = rig.tab.read(coneViewProvider);
        expect(shown?.isTransitive, isTrue);
        expect(shown?.root, const SelectedElement.cell(cellId: 'u_inv_7'));
        expect(find.byType(CruxUpgradeDialog), findsNothing);
      });
    }

    testWidgets('a build with no overlay says it requires NetCrux Pro', (
      tester,
    ) async {
      final rig = await _pump(
        tester,
        overrides: <Override>[
          betaPeriodProvider.overrideWithValue(true),
          proOverlayInstalledProvider.overrideWithValue(false),
        ],
      );
      _select(rig.tab, 'u_inv_7');
      rig.dispatcher.dispatch(
        rig.context,
        NetcruxAction.showConeViewAllLevels,
      );
      await tester.pump();
      expect(rig.tab.read(coneViewProvider), isNull);
      expect(
        find.text('Cone View, All Levels requires NetCrux Pro.'),
        findsOneWidget,
      );
    });

    testWidgets('an overlay with no walk bound says it requires NetCrux Pro', (
      tester,
    ) async {
      final rig = await _pump(
        tester,
        overrides: <Override>[
          betaPeriodProvider.overrideWithValue(true),
          proOverlayInstalledProvider.overrideWithValue(true),
        ],
      );
      _select(rig.tab, 'u_inv_7');
      rig.dispatcher.dispatch(
        rig.context,
        NetcruxAction.showConeViewAllLevels,
      );
      await tester.pump();
      expect(rig.tab.read(coneViewProvider), isNull);
      expect(
        find.text('Cone View, All Levels requires NetCrux Pro.'),
        findsOneWidget,
      );
    });
  });
}
