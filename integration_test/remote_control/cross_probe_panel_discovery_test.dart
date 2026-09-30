// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/cross_probe_panel_discovery_test.dart
//
// Verification driver for Open-Core Guide §6.5 (cross-probe panel —
// discovery + event log): boots the real open-core app, opens the real
// `CrossProbePanel` the same way `WorkspaceActionDispatcher
// ._onShowCrossProbePanel` does (a dialog hosting `CrossProbePanel()`
// against the live root `ProviderContainer`), then drives a genuine
// two-peer manifest exchange by starting a SECOND real `NetcruxCxpServer`
// in-process — the same raw-server-as-fake-peer technique
// `test/services/remote/cxp/netcrux_cxp_server_conformance_test.dart`'s
// `bootPair()` and `cxp_outbound_emitter_controller_test.dart`'s
// `_bootServerWithSubscribedClient()` use at the unit level — pointed at
// the same manifest directory as the booted app.
//
// This is real, not mocked: peer B writes an actual manifest file to
// disk, the app's `CxpDiscovery` watcher picks it up from the shared
// directory on its next scan, and the symmetric `CxpPeerConnector` on
// both sides dials the other so the app's own `LocalCxpServer` sees a
// real inbound Hello handshake — the same mechanism a second running
// suite product would go through. Assertions cover both halves of the
// panel: the "Peers" section (sourced from `cxpPeersProvider`, driven by
// file-based discovery) and the "Recent events" section (sourced from
// `cxpEventLogProvider`, driven by the server's own inbound/presence
// streams) — first via the presence "connected" event the two-peer
// handshake itself produces, then via a genuine inbound protocol message
// from a third raw peer dialing directly into the app's bound port (the
// same technique `notify_selection_emission_test.dart` and
// `request_highlight_navigation_test.dart` use), proving the event log's
// message path — not just its presence path — is live.

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/features/remote/providers/cxp_event_log_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';

import '../helpers/app_driver.dart';

/// The caption `crux_cxp_ui`'s CrossProbePanel renders for an inbound
/// `request_highlight` (CrossProbeEventKind.highlightReceived). Kept here as a
/// named constant so the coupling to the shared package's copy is explicit.
const String kHighlightReceivedLabel = 'Highlight received';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'cross-probe panel discovers a real peer via manifest exchange and the '
    'event log records both presence and inbound-message traffic (Guide §6.5)',
    (tester) async {
      final tmp = Directory.systemTemp.createTempSync(
        'netcrux_cross_probe_panel_it_',
      );
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } on FileSystemException {
          // best effort
        }
      });
      final manifestDir = '${tmp.path}/peers';

      await bootNetcrux(
        tester,
        extraOverrides: <Override>[
          // Hermetic manifest directory — shared with peer B below so the
          // two-peer exchange is real but confined to this test, never
          // touching the suite-shared discovery location or discovering
          // a real running suite product on the dev host.
          cxpManifestDirectoryProvider.overrideWith(
            (ref) async => manifestDir,
          ),
        ],
      );

      final root = rootContainer(tester);
      final appHost = await root.read(cxpServerHostProvider.future);
      expect(appHost, isNotNull, reason: 'cxpServerEnabled defaults to true');
      expect(appHost!.isAvailable, isTrue);
      final appIdentity = appHost.selfIdentity!;

      // Open the panel the same way the "Show Cross-Probe Panel" action
      // does (`WorkspaceActionDispatcher._onShowCrossProbePanel`): a
      // dialog hosting `CrossProbePanel()` against the live root context.
      // This is what keeps `cxpPeersProvider` / `cxpEventLogProvider` —
      // both `Stream` providers — actively listened; Riverpod pauses an
      // unlistened stream provider, so without a real watcher mounted the
      // discovery/event data would never actually flow into `.value`.
      //
      // `showDialog` needs a context with `Navigator`/`MaterialLocalizations`
      // ancestors — the `MaterialApp` widget's own element sits ABOVE those
      // (they're its descendants), so the context must come from something
      // mounted *inside* `MaterialApp`, e.g. its `Scaffold`.
      final appContext = tester.element(find.byType(Scaffold).first);
      unawaited(
        showDialog<void>(
          context: appContext,
          builder: (ctx) => const Dialog(
            child: SizedBox(
              width: 480,
              height: 480,
              child: NetCruxCrossProbePanel(),
            ),
          ),
        ),
      );
      final panelMounted = await pumpUntil(
        tester,
        () => tester.any(find.byType(NetCruxCrossProbePanel)),
      );
      expect(panelMounted, isTrue, reason: 'cross-probe panel never opened');

      // ── Peer B: a second real NetcruxCxpServer sharing the manifest
      // directory — the genuine two-peer manifest exchange.
      final peerB = NetcruxCxpServer(
        productVersion: '0.0.0-test',
        manifestDirectory: manifestDir,
      );
      await peerB.start();
      addTearDown(peerB.stop);
      final peerBIdentity = peerB.selfIdentity!;
      expect(
        peerBIdentity.peerId,
        isNot(appIdentity.peerId),
        reason: 'peer B must be a distinct peer from the app itself',
      );

      // ── Panel "Peers" section: discovery scans the shared manifest
      // directory (every ~2s) and picks up peer B's manifest.
      final peerDiscovered = await pumpUntil(
        tester,
        () =>
            root
                .read(cxpPeersProvider)
                .value
                ?.any(
                  (p) => p.identity.peerId == peerBIdentity.peerId,
                ) ??
            false,
        timeout: const Duration(seconds: 20),
      );
      expect(
        peerDiscovered,
        isTrue,
        reason: 'peer B never showed up in cxpPeersProvider',
      );
      await tester.pump();
      expect(
        find.textContaining(peerBIdentity.peerId),
        findsWidgets,
        reason: 'the panel never rendered the discovered peer',
      );

      // ── Panel "Recent events" section, presence half: the symmetric
      // `CxpPeerConnector` on peer B dials the app's server, so the app's
      // *server* (not just its discovery watcher) sees a real inbound
      // Hello — a presence "connected" entry lands in the event log.
      final presenceLogged = await pumpUntil(
        tester,
        () => root
            .read(cxpEventLogProvider)
            .any(
              (e) =>
                  e.direction == CxpEventDirection.presence &&
                  e.kind == 'connected' &&
                  e.peerLabel.contains(peerBIdentity.peerId),
            ),
        timeout: const Duration(seconds: 20),
      );
      expect(
        presenceLogged,
        isTrue,
        reason: 'peer B connecting never produced a presence event-log entry',
      );
      await tester.pump();
      expect(find.textContaining('connected'), findsWidgets);

      // ── Panel "Recent events" section, message half: a third raw peer
      // (same raw-socket-as-fake-peer technique as the sibling Guide §6.2/§6.3
      // integration tests) dials directly into the app's bound port and
      // sends a real protocol message, proving the event log's *message*
      // path — not just presence — updates live.
      final rawPeer = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: 'cross-probe-it-message-peer',
          productName: 'test-peer',
          productVersion: '0.0.0-test',
        ),
      );
      addTearDown(rawPeer.dispose);
      await rawPeer.connect(
        host: '127.0.0.1',
        port: appHost.boundPort!,
        token: cxpProcessAuthToken,
      );
      final ackFuture = rawPeer.inbound.firstWhere(
        (m) => m.message is RequestHighlightAck,
      );
      rawPeer.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.instance,
            path: 'top.no_such_cell:cell',
          ),
        ),
      );
      // Round trip on the Ack proves the server already processed (and
      // therefore already logged) the inbound request before we poll.
      await ackFuture.timeout(const Duration(seconds: 5));

      final messageLogged = await pumpUntil(
        tester,
        () => root
            .read(cxpEventLogProvider)
            .any(
              (e) =>
                  e.direction == CxpEventDirection.inbound &&
                  e.kind == CxpMessageKind.requestHighlight,
            ),
      );
      expect(
        messageLogged,
        isTrue,
        reason:
            'the request_highlight from the raw peer never reached the '
            'event log',
      );
      // The panel renders human labels, not raw wire kinds: NetCrux adopted
      // the shared `crux_cxp_ui` CrossProbePanel, which maps every known
      // CrossProbeEventKind to a caption ('Highlight received') and falls back
      // to the raw `messageKind` only for `other`. Asserting on
      // `request_highlight` was asserting the message is UNrecognized.
      final rowRendered = await pumpUntil(
        tester,
        () => find.text(kHighlightReceivedLabel).evaluate().isNotEmpty,
      );
      expect(
        rowRendered,
        isTrue,
        reason: 'the cross-probe panel never rendered the inbound highlight',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
