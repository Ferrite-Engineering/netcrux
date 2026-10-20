// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/remote/providers/cross_probe_visible_provider.dart';
import 'package:netcrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';

import '../../../helpers/telemetry_test_overrides.dart';

/// Every send the fake dispatcher saw in the current test.
final List<(PeerIdentity, CrossProbeSelection?)> _sent = [];

/// The shared send, replaced: it records what it was asked to send and
/// answers with [result].
class _FakeDispatcher extends CrossProbeDispatcher {
  _FakeDispatcher(this.result) : super(_unread);

  static T _unread<T>(ProviderListenable<T> provider) =>
      throw UnimplementedError('the fake reads nothing');

  final CrossProbeOutcomeKind result;

  @override
  Future<CrossProbeOutcome> send(
    PeerIdentity peer,
    CrossProbeSelection? selection, {
    String? label,
  }) async {
    _sent.add((peer, selection));
    return CrossProbeOutcome(
      result,
      target: label ?? cruxCxpDisplayName(peer.productName),
      reason: 'no design open',
    );
  }
}

const _peer = PeerIdentity(
  peerId: 'wavecrux-panel-peer',
  productName: 'wavecrux',
  productVersion: '1.2.3',
);

Key get _sendKey => const Key('cross_probe_send_wavecrux-panel-peer');

/// Mounts the docked panel directly in [container]'s scope — the production
/// shape, where the shared panel sits inside the active tab's provider scope
/// and reads its selection / hierarchy / project from the ambient container.
Widget _wrap(ProviderContainer container, {Locale? locale}) {
  return UncontrolledProviderScope(
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
      home: const Scaffold(body: NetCruxCrossProbePanel()),
    ),
  );
}

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
  const cpu = Module(
    name: 'cpu',
    attributes: <String, String>{},
    ports: {},
    cells: {},
    nets: {},
  );
  return const NetlistModel(
    creator: 'test',
    modules: <String, Module>{'top': top, 'cpu': cpu},
  );
}

/// A panel container: NetCrux's binding, [peers] connected (or the server off),
/// and the shared send replaced by [_FakeDispatcher].
ProviderContainer _boot({
  List<PeerIdentity> peers = const <PeerIdentity>[_peer],
  bool serverRunning = true,
  CrossProbeOutcomeKind result = CrossProbeOutcomeKind.sent,
  List<CxpDialFailure> unreachable = const <CxpDialFailure>[],
  List<Override> extra = const <Override>[],
}) {
  final container = ProviderContainer(
    overrides: [
      ...netcruxTelemetryTestOverrides(),
      cruxCxpProductBindingProvider.overrideWithValue(kNetcruxCxpBinding),
      cruxCxpPeersProvider.overrideWithValue(peers),
      cruxCxpServerStatusProvider.overrideWithValue((
        running: serverRunning,
        port: serverRunning ? 54323 : null,
        problem: null,
      )),
      cruxCxpUnreachablePeersProvider.overrideWith(
        (_) => Stream<List<CxpDialFailure>>.value(unreachable),
      ),
      cruxCxpRuntimeProvider.overrideWith((_) async => null),
      crossProbeDispatcherProvider.overrideWith(
        (ref) => _FakeDispatcher(result),
      ),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(_sent.clear);

  testWidgets('offline server renders the offline banner + placeholders', (
    tester,
  ) async {
    final container = _boot(peers: const [], serverRunning: false);
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    final strings = CruxCxpStrings.forLocale(
      const Locale('en'),
      product: 'NetCrux',
    );
    expect(find.text(strings.serverOffline), findsOneWidget);
    expect(find.text(strings.noPeers), findsOneWidget);
    expect(find.text(strings.noEvents), findsOneWidget);
  });

  testWidgets('locale sweep renders without exception', (tester) async {
    const locales = <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ];
    for (final loc in locales) {
      final container = _boot(peers: const [], serverRunning: false);
      await tester.pumpWidget(_wrap(container, locale: loc));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'locale $loc must render');
    }
  });

  testWidgets('a dial failure renders a persistent unreachable-peer row', (
    tester,
  ) async {
    final container = _boot(
      peers: const [],
      unreachable: const <CxpDialFailure>[
        CxpDialFailure(
          peerId: 'wavecrux-unreachable',
          host: '127.0.0.1',
          port: 4242,
          error: 'connection refused',
          consecutiveFailures: 3,
          nextRetryAfterTicks: 3,
        ),
      ],
    );
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    expect(find.byKey(const Key('cross_probe_unreachable')), findsOneWidget);
    expect(find.text('wavecrux-unreachable'), findsOneWidget);
  });

  group('per-peer direct send', () {
    testWidgets('sends the ambient selection tagged with design_id', (
      tester,
    ) async {
      final container = _boot();
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_cpu'));
      // A loaded design gives the sender a design id to attach.
      container.read(currentProjectProvider.notifier).setSourceFiles(<String>[
        '/designs/cdc_capture/cdc_capture.v',
      ]);

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.tap(find.byKey(_sendKey));
      await tester.pump();

      expect(_sent, hasLength(1));
      final (peer, selection) = _sent.single;
      expect(peer.peerId, 'wavecrux-panel-peer');
      // One candidate: the instance, as the clean dot-joined name (no `:cell`
      // marker) so a receiver can leaf-match it.
      expect(selection!.candidates, hasLength(1));
      expect(selection.candidates.single.path, 'top.u_cpu');
      expect(selection.candidates.single.kind, ElementKind.instance);
      expect(selection.displayName, 'u_cpu');
      expect(selection.metadata['netcrux.scope_path'], isNotNull);
      expect(
        selection.metadata[cxpDesignIdMetadataKey],
        cxpDesignIdForPath('/designs/cdc_capture/cdc_capture.v'),
        reason:
            'the sender must attach crux.design_id for the shared-workspace '
            'fallback',
      );
    });

    testWidgets('a wire selection resolves to the net element kind', (
      tester,
    ) async {
      final container = _boot();
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.wire(netId: 7, edgeId: 'e_7_0'));

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.tap(find.byKey(_sendKey));
      await tester.pump();

      expect(_sent.single.$2!.candidates.single.kind, ElementKind.net);
    });

    testWidgets('an empty selection hands the shared send nothing', (
      tester,
    ) async {
      final container = _boot();
      container.read(hierarchyTreeProvider.notifier).setModel(_model());

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.tap(find.byKey(_sendKey));
      await tester.pump();

      // The shared send reports "nothing selected" itself; what it was handed
      // is null, never a selection with nothing in it.
      expect(_sent.single.$2, isNull);
    });

    group('sending is free in every edition', () {
      // Cross-probing is free across the board, sending as well as
      // receiving: the panel's send button carries no tier chip and never
      // raises an upgrade dialog. Every case selects a cell so the send has
      // something to carry.
      ProviderContainer seat({required bool beta, required LicenseTier tier}) {
        final container = _boot(
          extra: [
            betaPeriodProvider.overrideWithValue(beta),
            licenseTierProvider.overrideWithValue(tier),
          ],
        );
        container.read(hierarchyTreeProvider.notifier).setModel(_model());
        container
            .read(selectedElementProvider.notifier)
            .select(const SelectedElement.cell(cellId: 'u_cpu'));
        return container;
      }

      for (final (beta, tier) in <(bool, LicenseTier)>[
        (false, LicenseTier.openCore),
        (false, LicenseTier.pro),
        (true, LicenseTier.openCore),
      ]) {
        testWidgets('beta=$beta at ${tier.name}: the send goes through with '
            'no upgrade dialog', (tester) async {
          await tester.pumpWidget(_wrap(seat(beta: beta, tier: tier)));
          await tester.pump();
          await tester.tap(find.byKey(_sendKey));
          await tester.pump();
          expect(_sent, hasLength(1));
          expect(find.byType(CruxUpgradeDialog), findsNothing);
        });
      }

      testWidgets('the send button wears no tier chip', (tester) async {
        final container = seat(beta: false, tier: LicenseTier.openCore);
        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        expect(find.byKey(_sendKey), findsOneWidget);
        expect(find.byType(FeatureTierBadge), findsNothing);
        expect(
          find.byKey(const Key('cross_probe_send_badge_wavecrux-panel-peer')),
          findsNothing,
        );
      });
    });

    testWidgets('a refused send is an error toast naming the peer and why', (
      tester,
    ) async {
      final container = _boot(result: CrossProbeOutcomeKind.refused);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_cpu'));

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.tap(find.byKey(_sendKey));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Cross-probe to WaveCrux: no design open'),
        findsOneWidget,
      );
    });
  });

  testWidgets("the panel's close button hides the docked tab", (tester) async {
    final container = _boot();
    container.read(crossProbeVisibleProvider.notifier).set(visible: true);
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    final panel = tester.widget<CruxCrossProbePanel>(
      find.byType(CruxCrossProbePanel),
    );
    panel.onClose();

    expect(container.read(crossProbeVisibleProvider), isFalse);
  });
}
