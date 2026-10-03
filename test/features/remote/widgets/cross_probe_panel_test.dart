// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/remote/providers/cross_probe_originate_gate_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_dial_failures_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_event_log_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// Mounts the docked panel directly in [container]'s scope — the production
/// shape, where the shared panel sits inside the active tab's provider scope
/// and reads its selection / hierarchy / project from the ambient container.
Widget _wrap(
  ProviderContainer container, {
  Locale? locale,
  Widget panel = const NetCruxCrossProbePanel(),
}) {
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
      home: Scaffold(body: panel),
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

const _peerEntry = CxpPeerEntry(
  identity: PeerIdentity(
    peerId: 'wavecrux-panel-peer',
    productName: 'wavecrux',
    productVersion: '1.2.3',
  ),
  host: '127.0.0.1',
  port: 4242,
);

Key get _sendKey => const Key('cross_probe_send_wavecrux-panel-peer');

void main() {
  testWidgets('offline server renders the offline banner + placeholders', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        cxpServerHostProvider.overrideWith(_NullCxpServerHost.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    final l10n = await L10N.delegate.load(const Locale('en'));
    expect(find.text(l10n.crossProbeServerOffline), findsOneWidget);
    expect(find.text(l10n.crossProbePanelNoPeers), findsOneWidget);
    expect(find.text(l10n.crossProbePanelNoEvents), findsOneWidget);
  });

  testWidgets('locale sweep renders without exception', (tester) async {
    const locales = <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ];
    for (final loc in locales) {
      final container = ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          cxpServerHostProvider.overrideWith(_NullCxpServerHost.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_wrap(container, locale: loc));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'locale $loc must render');
    }
  });

  testWidgets('a dial failure renders a persistent unreachable-peer row', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        cxpServerHostProvider.overrideWith(_NullCxpServerHost.new),
        cxpDialFailuresProvider.overrideWith(
          (ref) => Stream<List<CxpDialFailure>>.value(
            const <CxpDialFailure>[
              CxpDialFailure(
                peerId: 'wavecrux-unreachable',
                host: '127.0.0.1',
                port: 4242,
                error: 'connection refused',
                consecutiveFailures: 3,
                nextRetryAfterTicks: 3,
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    expect(find.byKey(const Key('cross_probe_unreachable')), findsOneWidget);
    expect(find.text('wavecrux-unreachable'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('no unreachable-peer row when every peer is reachable', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        cxpServerHostProvider.overrideWith(_NullCxpServerHost.new),
        cxpDialFailuresProvider.overrideWith(
          (ref) => Stream<List<CxpDialFailure>>.value(const <CxpDialFailure>[]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    expect(find.byKey(const Key('cross_probe_unreachable')), findsNothing);
  });

  group('the send-failure toast is in the user language', _localizedToastTests);

  group('per-peer direct send', () {
    late _RecordingCxpServer wire;

    /// A panel with one peer to send to. Sending is Pro, and the beta is
    /// over, so the seat holds Pro unless [tier] says otherwise; the tier
    /// gate's own cases set both sides explicitly.
    ProviderContainer boot({
      bool serverRunning = true,
      bool deliver = true,
      bool ackHonored = true,
      String? ackReason,
      LicenseTier? tier = LicenseTier.pro,
      List<Override> extra = const <Override>[],
    }) {
      wire = _RecordingCxpServer(
        deliver: deliver,
        ackHonored: ackHonored,
        ackReason: ackReason,
      );
      return ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          cxpServerHostProvider.overrideWith(
            () => serverRunning
                ? _StaticHost(_StubNetcruxServer(wire))
                : _NullCxpServerHost(),
          ),
          cxpPeersProvider.overrideWith(
            (ref) => Stream<List<CxpPeerEntry>>.value(
              const <CxpPeerEntry>[_peerEntry],
            ),
          ),
          if (tier != null) licenseTierProvider.overrideWithValue(tier),
          ...extra,
        ],
      );
    }

    testWidgets('sends the ambient selection tagged with design_id', (
      tester,
    ) async {
      final container = boot();
      addTearDown(container.dispose);
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
      // The panel's ack-bearing send resolves on the wire's real async reply,
      // so it needs the real event loop. Poll for it rather than sleeping a
      // fixed 20ms and hoping: on a loaded runner the reply lands later and
      // the assertion below fails complaining about the message instead.
      await _pumpUntilReal(
        tester,
        () => container
            .read(cxpEventLogProvider)
            .any((e) => e.direction == CxpEventDirection.outbound),
        description: 'the outbound row reaching the CXP event log',
      );

      expect(wire.sent, hasLength(1));
      final (peerId, message) = wire.sent.single;
      expect(peerId, 'wavecrux-panel-peer');
      // The explicit panel send is now the ack-bearing request_highlight,
      // not fire-and-forget notify_selection — so a rejected send can be
      // surfaced to the user.
      final request = message as RequestHighlight;
      // Clean dot-joined instance name (no `:cell` marker) — cross-probe fix.
      expect(request.element.path, 'top.u_cpu');
      expect(request.element.kind, ElementKind.instance);
      expect(request.metadata['netcrux.scope_path'], isNotNull);
      expect(
        request.metadata[cxpDesignIdMetadataKey],
        cxpDesignIdForPath('/designs/cdc_capture/cdc_capture.v'),
        reason:
            'the sender must attach crux.design_id for the shared-workspace fallback',
      );
      // The send is mirrored into the shared event log as an outbound row.
      final events = container.read(cxpEventLogProvider);
      final outbound = events.firstWhere(
        (e) => e.direction == CxpEventDirection.outbound,
      );
      expect(outbound.kind, CxpMessageKind.requestHighlight);
    });

    testWidgets('a wire selection resolves to the net element kind', (
      tester,
    ) async {
      final container = boot();
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.wire(netId: 7, edgeId: 'e_7_0'));

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.tap(find.byKey(_sendKey));
      await _pumpUntilReal(
        tester,
        () => container
            .read(cxpEventLogProvider)
            .any((e) => e.direction == CxpEventDirection.outbound),
        description: 'the outbound row reaching the CXP event log',
      );

      final (_, message) = wire.sent.single;
      expect((message as RequestHighlight).element.kind, ElementKind.net);
    });

    testWidgets('an empty selection sends nothing', (tester) async {
      final container = boot();
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.tap(find.byKey(_sendKey));
      await tester.pump();

      expect(wire.sent, isEmpty);
    });

    group('the send button is a route to a Pro capability', () {
      // Origination is sold as Pro. The Pro overlay gates its own route (the
      // schematic context menu's "Send to …" entries); this panel ships in
      // open core and its send button reaches the same capability, so it has
      // to gate too. Every case selects a cell so that, absent a gate, the
      // send WOULD go through — which is what made the button a bypass.
      ProviderContainer gated({
        required bool beta,
        required LicenseTier tier,
        List<Override> extra = const <Override>[],
      }) {
        final container = boot(
          tier: null,
          extra: [
            betaPeriodProvider.overrideWithValue(beta),
            licenseTierProvider.overrideWithValue(tier),
            ...extra,
          ],
        );
        addTearDown(container.dispose);
        container.read(hierarchyTreeProvider.notifier).setModel(_model());
        container
            .read(selectedElementProvider.notifier)
            .select(const SelectedElement.cell(cellId: 'u_cpu'));
        return container;
      }

      testWidgets('post-beta at Open Core: nothing is sent, and the upgrade '
          'dialog says why', (tester) async {
        final container = gated(beta: false, tier: LicenseTier.openCore);
        await tester.pumpWidget(_wrap(container));
        await tester.pump();
        await tester.tap(find.byKey(_sendKey));
        await tester.pumpAndSettle();

        expect(
          wire.sent,
          isEmpty,
          reason:
              'the panel is open core and the send button reaches a Pro '
              'capability; without a gate here the overlay menu gate is a '
              'paywall with a second door',
        );
        expect(
          find.byType(CruxUpgradeDialog),
          findsOneWidget,
          reason: 'a denied press is never silent',
        );
      });

      // Admitted sends complete on the wire's real async reply and then
      // mirror into the event log; waiting on the mirror, as every other
      // send test here does, keeps the test from finishing mid-chain.
      Future<void> sendAndSettle(
        WidgetTester tester,
        ProviderContainer container,
      ) async {
        await tester.pumpWidget(_wrap(container));
        await tester.pump();
        await tester.tap(find.byKey(_sendKey));
        await _pumpUntilReal(
          tester,
          () => container
              .read(cxpEventLogProvider)
              .any((e) => e.direction == CxpEventDirection.outbound),
          description: 'the outbound row reaching the CXP event log',
        );
      }

      testWidgets('post-beta at Pro: the send goes through', (tester) async {
        await sendAndSettle(tester, gated(beta: false, tier: LicenseTier.pro));
        expect(wire.sent, hasLength(1));
        expect(find.byType(CruxUpgradeDialog), findsNothing);
      });

      testWidgets('during the beta every tier sends', (tester) async {
        await sendAndSettle(
          tester,
          gated(beta: true, tier: LicenseTier.openCore),
        );
        expect(wire.sent, hasLength(1));
        expect(find.byType(CruxUpgradeDialog), findsNothing);
      });

      testWidgets('the panel asks the gate seam', (tester) async {
        // A tier the default gate would ADMIT, so a send that still gets
        // through can only mean the seam was bypassed.
        var asked = 0;
        final container = gated(
          beta: true,
          tier: LicenseTier.pro,
          extra: [
            crossProbeOriginateGateProvider.overrideWith(
              (ref) => (_) {
                asked++;
                return false;
              },
            ),
          ],
        );
        await tester.pumpWidget(_wrap(container));
        await tester.pump();
        await tester.tap(find.byKey(_sendKey));
        await tester.pump();
        expect(asked, 1);
        expect(wire.sent, isEmpty);
      });

      // Badge before the click (crux-shared#8): the gate above only speaks
      // once the button is pressed, and every other gated control in the
      // suite is labelled before that.
      Finder sendBadge() => find.descendant(
        of: find.byKey(const Key('cross_probe_send_badge_wavecrux-panel-peer')),
        matching: find.byType(FeatureTierBadge),
      );

      testWidgets('post-beta at Open Core: the send button wears its PRO '
          'badge before it is pressed', (tester) async {
        final container = gated(beta: false, tier: LicenseTier.openCore);
        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        expect(wire.sent, isEmpty, reason: 'nothing has been pressed');
        expect(sendBadge(), findsOneWidget);
        final badge = tester.widget<FeatureTierBadge>(sendBadge());
        expect(badge.requiredTier, kCrossProbeOriginateRequiredTier);
        final l10n = await L10N.delegate.load(const Locale('en'));
        expect(
          find.descendant(
            of: sendBadge(),
            matching: find.text(l10n.tierBadgePro),
          ),
          findsOneWidget,
        );
        expect(
          tester.getCenter(sendBadge()).dx,
          lessThan(tester.getCenter(find.byKey(_sendKey)).dx),
          reason: 'the badge leads the button it labels',
        );
      });

      testWidgets('the badge names the feature, not the seat: it shows at '
          'Pro and during the beta too', (tester) async {
        for (final (beta, tier) in <(bool, LicenseTier)>[
          (false, LicenseTier.pro),
          (true, LicenseTier.openCore),
        ]) {
          final container = gated(beta: beta, tier: tier);
          await tester.pumpWidget(_wrap(container));
          await tester.pump();
          expect(sendBadge(), findsOneWidget, reason: 'beta=$beta tier=$tier');
        }
      });
    });

    testWidgets('a rejected send (honored:false ack) raises a panel toast', (
      tester,
    ) async {
      final container = boot(
        ackHonored: false,
        ackReason: 'Element not found in current design',
      );
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_cpu'));

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.tap(find.byKey(_sendKey));
      // _sendTo awaits the peer's ack (delivered by the wire in real async),
      // then pushes the failure; the toaster schedules a post-frame snackbar.
      await _pumpUntilReal(
        tester,
        () => container
            .read(cxpEventLogProvider)
            .any((e) => e.direction == CxpEventDirection.outbound),
        description: 'the outbound row reaching the CXP event log',
      );
      await tester.pump(); // run the post-frame callback → showSnackBar
      await tester.pump(const Duration(milliseconds: 300)); // animate in

      // The send still reached the wire.
      expect(wire.sent, hasLength(1));
      expect(
        find.byKey(const Key('cross_probe_send_failure')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Element not found in current design'),
        findsOneWidget,
      );
    });

    testWidgets('a send the peer never receives raises a panel toast', (
      tester,
    ) async {
      // The wire refuses the send: the peer went away after the panel listed
      // it, so the request is never delivered and no ack will come.
      final container = boot(deliver: false);
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_cpu'));

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      final toast = find.byKey(const Key('cross_probe_send_failure'));
      await tester.tap(find.byKey(_sendKey));
      // The wrapper's refusal path settles on the real event loop (it cancels
      // its ack subscription), so wait on the outcome rather than a pump
      // count. A timeout here is the failure: nothing was shown.
      await _pumpUntilReal(
        tester,
        () => toast.evaluate().isNotEmpty,
        description: 'the send-failure toast',
      );
      await tester.pump(const Duration(milliseconds: 300)); // animate in

      expect(wire.sent, hasLength(1));
      expect(
        toast,
        findsOneWidget,
        reason:
            'a send is never a silent no-op; a press that reached nobody '
            'must say so',
      );
      expect(
        find.descendant(of: toast, matching: find.textContaining('wavecrux')),
        findsOneWidget,
        reason: 'the toast names the peer the send did not reach',
      );
    });

    testWidgets('closing the panel while a send waits for its ack neither '
        'throws nor loses the logged, counted exchange', (tester) async {
      final ackWait = Completer<void>();
      final telemetry = _RecordingTelemetry();
      wire = _RecordingCxpServer(deliver: true);
      final showPanel = ValueNotifier<bool>(true);
      addTearDown(showPanel.dispose);
      final container = ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          telemetryServiceProvider.overrideWithValue(telemetry),
          // Sending is Pro and the beta is over.
          licenseTierProvider.overrideWithValue(LicenseTier.pro),
          cxpServerHostProvider.overrideWith(
            () => _StaticHost(
              _ScriptedNetcruxServer(
                wire,
                // A refusal, so the send would also raise the failure toast
                // on the panel that is no longer there.
                ackHonored: false,
                ackWait: ackWait.future,
              ),
            ),
          ),
          cxpPeersProvider.overrideWith(
            (ref) => Stream<List<CxpPeerEntry>>.value(
              const <CxpPeerEntry>[_peerEntry],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_cpu'));

      await tester.pumpWidget(
        _wrap(
          container,
          panel: ValueListenableBuilder<bool>(
            valueListenable: showPanel,
            builder: (_, show, _) =>
                show ? const NetCruxCrossProbePanel() : const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(_sendKey));
      await tester.pump();
      expect(wire.sent, hasLength(1));

      // The user closes the panel inside the ack wait (up to five seconds in
      // the real server), which disposes the controller and its notifiers.
      showPanel.value = false;
      await tester.pump();
      expect(find.byType(NetCruxCrossProbePanel), findsNothing);

      ackWait.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        container
            .read(cxpEventLogProvider)
            .where((e) => e.direction == CxpEventDirection.outbound),
        hasLength(1),
        reason:
            'the request reached the peer; the app-wide log still records '
            'it after the panel closed',
      );
      final probes = telemetry.events
          .where((e) => e.name == 'cxp.crossprobe')
          .toList();
      expect(probes, hasLength(1), reason: 'and it still counts');
      expect(probes.single.properties, containsPair('honored', false));
    });

    testWidgets('a second refused send to the same peer raises its own toast', (
      tester,
    ) async {
      // Two refusals from one peer with one reason compare equal. Published
      // as-is, the second would not notify the panel and would be silent.
      wire = _RecordingCxpServer(deliver: true);
      final container = ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          // Sending is Pro and the beta is over.
          licenseTierProvider.overrideWithValue(LicenseTier.pro),
          cxpServerHostProvider.overrideWith(
            () => _StaticHost(
              _ScriptedNetcruxServer(
                wire,
                ackHonored: false,
                ackReason: 'Element not found in current design',
              ),
            ),
          ),
          cxpPeersProvider.overrideWith(
            (ref) => Stream<List<CxpPeerEntry>>.value(
              const <CxpPeerEntry>[_peerEntry],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_cpu'));
      final toast = find.byKey(const Key('cross_probe_send_failure'));

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.tap(find.byKey(_sendKey));
      await tester.pumpAndSettle();
      expect(toast, findsOneWidget);

      // The first toast is gone by the time the user tries again.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(toast, findsNothing);

      await tester.tap(find.byKey(_sendKey));
      await tester.pumpAndSettle();
      expect(wire.sent, hasLength(2));
      expect(toast, findsOneWidget, reason: 'the second press is not silent');
    });
  });
}

void _localizedToastTests() {
  // The shared panel falls back to English for this toast. Without the app's
  // strings it stayed English in every locale.
  Future<void> sendAndSettle(
    WidgetTester tester, {
    required Locale locale,
    String? reason,
  }) async {
    final wire = _RecordingCxpServer(deliver: true);
    final container = ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        // Sending is Pro and the beta is over; this is about the toast.
        licenseTierProvider.overrideWithValue(LicenseTier.pro),
        cxpServerHostProvider.overrideWith(
          () => _StaticHost(
            _ScriptedNetcruxServer(wire, ackHonored: false, ackReason: reason),
          ),
        ),
        cxpPeersProvider.overrideWith(
          (ref) => Stream<List<CxpPeerEntry>>.value(
            const <CxpPeerEntry>[_peerEntry],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(hierarchyTreeProvider.notifier).setModel(_model());
    container
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'u_cpu'));
    await tester.pumpWidget(_wrap(container, locale: locale));
    await tester.pump();
    await tester.tap(find.byKey(_sendKey));
    await tester.pumpAndSettle();
  }

  for (final locale in const [
    Locale('en'),
    Locale('zh', 'CN'),
    Locale('zh'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    testWidgets('a refusal with no reason, in $locale', (tester) async {
      await sendAndSettle(tester, locale: locale);
      expect(
        find.text(lookupL10N(locale).crossProbeSendFailed('wavecrux')),
        findsOneWidget,
      );
    });

    testWidgets('a refusal with the peer reason, in $locale', (tester) async {
      const reason = 'Element not found in current design';
      await sendAndSettle(tester, locale: locale, reason: reason);
      expect(
        find.text(lookupL10N(locale).crossProbeSendRefused('wavecrux', reason)),
        findsOneWidget,
        reason: 'the frame is translated; the reason is the peer words',
      );
    });
  }
}

/// Keeps every telemetry event it is handed.
class _RecordingTelemetry implements TelemetryService {
  final events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);
}

/// A [_StubNetcruxServer] whose `requestHighlight` answers from a script
/// instead of the wire's inbound stream, so a test can hold the ack (the real
/// server waits up to five seconds for it) and release it on the fake clock.
/// Every request is still recorded on the wire.
class _ScriptedNetcruxServer extends _StubNetcruxServer {
  _ScriptedNetcruxServer(
    super._wire, {
    this.ackHonored = true,
    this.ackReason,
    this.ackWait,
  });

  final bool ackHonored;
  final String? ackReason;
  final Future<void>? ackWait;

  @override
  Future<({bool delivered, RequestHighlightAck? ack})> requestHighlight(
    String peerId,
    RequestHighlight request, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _wire.sent.add((peerId, request));
    if (ackWait != null) await ackWait;
    return (
      delivered: true,
      ack: RequestHighlightAck(
        inReplyTo: 'req',
        honored: ackHonored,
        reason: ackReason,
      ),
    );
  }
}

/// Records what the panel hands to the wire without binding a socket, and — so
/// the panel's ack-bearing `requestHighlight` completes — injects a
/// `RequestHighlightAck` back on the inbound stream for each request_highlight.
/// Hands the real event loop time in slices until [condition] holds.
///
/// The panel's send awaits the peer's ack, which the fake wire delivers in
/// real async, so the fake clock alone never completes it. `runAsync` gives it
/// the real loop; the `pump()` between slices drains the fake-async zone so a
/// continuation queued there can run.
///
/// This replaces three copies of a fixed 20ms sleep. The sleep was not wrong
/// on any machine it was written on — it was a bet on how loaded the runner
/// is, and losing that bet surfaced as an assertion about the *message*, not
/// about timing, which is the expensive kind of flake to diagnose.
///
/// Every caller waits on the **event-log mirror**, not on `wire.sent`. The
/// send is not the last thing to happen: the panel awaits the peer's ack, then
/// mirrors the exchange into the CXP event log, then (on rejection) raises a
/// toast. Polling for `wire.sent` resumes the test in the middle of that
/// chain, and the test then completes while the panel is still running — which
/// surfaces as `Bad state: Using "ref" ... has been unmounted` thrown *after*
/// the test passed. The fixed sleep this replaced happened to be long enough
/// to cover the whole chain, which is why the shape survived.
Future<void> _pumpUntilReal(
  WidgetTester tester,
  bool Function() condition, {
  String description = 'condition',
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('$description not satisfied within $timeout');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

class _RecordingCxpServer extends LocalCxpServer {
  _RecordingCxpServer({
    required this.deliver,
    this.ackHonored = true,
    this.ackReason,
  }) : super(
         selfIdentity: const PeerIdentity(
           peerId: 'netcrux-under-test',
           productName: 'netcrux',
           productVersion: '0.0.0-test',
         ),
       );

  final bool deliver;
  final bool ackHonored;
  final String? ackReason;

  final List<(String, CxpMessage)> sent = <(String, CxpMessage)>[];

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  int? get boundPort => 4200;

  @override
  bool sendTo(String peerId, CxpMessage message) {
    sent.add((peerId, message));
    if (deliver && message is RequestHighlight) {
      // Simulate the peer replying, so the wrapper's requestHighlight() future
      // resolves within the test's pumps rather than hanging on its timeout.
      injectInbound(
        InboundCxpMessage(
          from: PeerIdentity(
            peerId: peerId,
            productName: peerId,
            productVersion: '0',
          ),
          envelope: CxpEnvelope(
            messageId: 'ack-for-$peerId',
            from: peerId,
            kind: CxpMessageKind.requestHighlightAck,
            payload: const <String, Object?>{},
          ),
          message: RequestHighlightAck(
            inReplyTo: 'req',
            honored: ackHonored,
            reason: ackReason,
          ),
        ),
      );
    }
    return deliver;
  }
}

class _NullCxpServerHost extends CxpServerHost {
  @override
  Future<NetcruxCxpServer?> build() async => null;
}

class _StaticHost extends CxpServerHost {
  _StaticHost(this._server);

  final NetcruxCxpServer _server;

  @override
  Future<NetcruxCxpServer?> build() async => _server;
}

/// A [NetcruxCxpServer] that exposes a recording wire without starting
/// sockets, the manifest writer, or the discovery watcher.
class _StubNetcruxServer extends NetcruxCxpServer {
  _StubNetcruxServer(this._wire)
    : super(productVersion: '0.0.0-test', manifestDirectory: '');

  final _RecordingCxpServer _wire;

  @override
  LocalCxpServer? get server => _wire;
}
