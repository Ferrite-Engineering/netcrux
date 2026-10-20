// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/workspace/services/workspace_action_dispatcher.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';

import '../../helpers/telemetry_test_overrides.dart';

/// The Cross-probe Selection command: View > Cross-probe Selection…, the
/// palette entry and Cmd/Ctrl+Shift+Enter all dispatch
/// `NetcruxAction.crossProbeSelection`, which sends the active tab's selection
/// through the shared send.

/// Every send the fake dispatcher saw in the current test.
final List<(PeerIdentity, CrossProbeSelection?)> _sent = [];

class _FakeDispatcher extends CrossProbeDispatcher {
  _FakeDispatcher() : super(_unread);

  static T _unread<T>(ProviderListenable<T> provider) =>
      throw UnimplementedError('the fake reads nothing');

  @override
  Future<CrossProbeOutcome> send(
    PeerIdentity peer,
    CrossProbeSelection? selection, {
    String? label,
  }) async {
    _sent.add((peer, selection));
    return CrossProbeOutcome(
      CrossProbeOutcomeKind.sent,
      target: label ?? cruxCxpDisplayName(peer.productName),
    );
  }
}

PeerIdentity _peer(String product, int startedAt) => PeerIdentity(
  peerId: '$product-7-$startedAt',
  productName: product,
  productVersion: '1.2.0',
);

NetlistModel _model() {
  const top = Module(
    name: 'top',
    attributes: <String, String>{'top': '1'},
    ports: {},
    cells: <String, Cell>{
      'u_cpu': Cell(
        name: 'u_cpu',
        type: 'cpu',
        parameters: {},
        attributes: {},
        portDirections: {},
        connections: {},
      ),
    },
    nets: {},
  );
  return const NetlistModel(
    creator: 'test',
    modules: <String, Module>{'top': top},
  );
}

typedef _Rig = ({
  WorkspaceActionDispatcher dispatcher,
  BuildContext context,
  ProviderContainer tab,
});

/// A workspace with one open tab holding a design, the CXP lifecycle bound with
/// [peers] connected, and the shared send replaced by the fake.
Future<_Rig> _pumpApp(
  WidgetTester tester, {
  required List<PeerIdentity> peers,
  bool selectCell = true,
}) async {
  final root = ProviderContainer(
    overrides: [
      ...netcruxTelemetryTestOverrides(),
      cruxCxpProductBindingProvider.overrideWithValue(kNetcruxCxpBinding),
      cruxCxpPeersProvider.overrideWithValue(peers),
      cruxCxpServerStatusProvider.overrideWithValue((
        running: true,
        port: 54323,
        problem: null,
      )),
      cruxCxpRuntimeProvider.overrideWith((_) async => null),
      crossProbeDispatcherProvider.overrideWith((ref) => _FakeDispatcher()),
      netcruxWorkspaceProvider.overrideWith(
        () => NetcruxWorkspaceNotifier(
          service: WorkspaceService<NetcruxTabPayload>(
            codec: const NetcruxWorkspaceCodec(),
            directoryFactory: () async =>
                Directory.systemTemp.createTempSync('nc_cross_probe_cmd_'),
            logger: (_) {},
          ),
          autoSaveDebounce: Duration.zero,
          restoreGate: () async => true,
        ),
      ),
    ],
  );
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
        displayName: 'top',
        payload: const NetcruxTabPayload(
          sourceFiles: <String>[],
          topModule: 'top',
        ),
      );
  final tabId = root.read(netcruxWorkspaceProvider).value!.activeTabId!;
  final tab = tabs.containerFor(tabId);
  tab.read(hierarchyTreeProvider.notifier).setModel(_model());
  if (selectCell) {
    tab
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'u_cpu'));
  }

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
            body: Column(
              children: [
                const TextField(key: Key('field')),
                Expanded(
                  child: Consumer(
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
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(() => tester.pump(const Duration(seconds: 10)));
  return (dispatcher: dispatcher, context: hostContext, tab: tab);
}

void main() {
  setUp(_sent.clear);

  testWidgets('with one product running it sends at once, no menu', (
    tester,
  ) async {
    final rig = await _pumpApp(tester, peers: [_peer('wavecrux', 1)]);

    rig.dispatcher.dispatch(rig.context, NetcruxAction.crossProbeSelection);
    await tester.pumpAndSettle();

    final (peer, selection) = _sent.single;
    expect(peer.productName, 'wavecrux');
    expect(selection!.candidates.single.kind, ElementKind.instance);
    expect(selection.candidates.single.path, 'top.u_cpu');
    expect(find.byType(PopupMenuItem<int>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with several products running it opens their list as a menu', (
    tester,
  ) async {
    final rig = await _pumpApp(
      tester,
      peers: [_peer('wavecrux', 1), _peer('lintcrux', 1)],
    );

    rig.dispatcher.dispatch(rig.context, NetcruxAction.crossProbeSelection);
    await tester.pumpAndSettle();
    expect(_sent, isEmpty, reason: 'the user chooses the target');
    expect(find.text('WaveCrux'), findsOneWidget);
    expect(find.text('LintCrux'), findsOneWidget);

    await tester.tap(find.text('LintCrux'));
    await tester.pumpAndSettle();

    expect(_sent.single.$1.productName, 'lintcrux');
  });

  testWidgets('nothing selected says so and sends nothing', (tester) async {
    final rig = await _pumpApp(
      tester,
      peers: [_peer('wavecrux', 1)],
      selectCell: false,
    );

    rig.dispatcher.dispatch(rig.context, NetcruxAction.crossProbeSelection);
    await tester.pumpAndSettle();

    expect(_sent, isEmpty);
    expect(
      find.text('Select something to cross-probe first.'),
      findsOneWidget,
    );
  });

  testWidgets('with no peer running it says so', (tester) async {
    final rig = await _pumpApp(tester, peers: const []);

    rig.dispatcher.dispatch(rig.context, NetcruxAction.crossProbeSelection);
    await tester.pumpAndSettle();

    expect(_sent, isEmpty);
    expect(
      find.text('No peers are running to cross-probe to.'),
      findsOneWidget,
    );
  });

  testWidgets('a focused text field keeps the key: nothing is sent', (
    tester,
  ) async {
    final rig = await _pumpApp(tester, peers: [_peer('wavecrux', 1)]);
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();

    rig.dispatcher.dispatch(rig.context, NetcruxAction.crossProbeSelection);
    await tester.pumpAndSettle();

    expect(_sent, isEmpty);
    expect(find.text('Select something to cross-probe first.'), findsNothing);
  });
}
