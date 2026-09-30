// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart' as cxp_ui;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/remote/providers/cross_probe_originate_gate_provider.dart';
import 'package:netcrux/features/remote/providers/cross_probe_visible_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_dial_failures_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_event_log_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/cxp_selection_resolver.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';

/// NetCrux's docked cross-probe panel.
///
/// A thin `ConsumerStatefulWidget` host around the shared
/// `crux_cxp_ui.CrossProbePanel`: it owns a [NetCruxCrossProbePanelController]
/// that bridges NetCrux's live CXP Riverpod state into the panel's reactive
/// contract, and disposes it with the widget. NetCrux's old modal `AlertDialog`
/// presentation of the panel is retired in favour of this docked side-panel,
/// which `NetcruxRightDock` lists as a right-dock tab when
/// `crossProbeVisibleProvider` is set.
///
/// The shared widget is *also* named `CrossProbePanel`, so it is imported with
/// the `cxp_ui` prefix and this host is named distinctly.
class NetCruxCrossProbePanel extends ConsumerStatefulWidget {
  /// Creates the docked cross-probe panel.
  const NetCruxCrossProbePanel({super.key});

  @override
  ConsumerState<NetCruxCrossProbePanel> createState() =>
      _NetCruxCrossProbePanelState();
}

class _NetCruxCrossProbePanelState
    extends ConsumerState<NetCruxCrossProbePanel> {
  late final NetCruxCrossProbePanelController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NetCruxCrossProbePanelController(ref);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return cxp_ui.CrossProbePanel(
      controller: _controller,
      // Docked as a CruxDock tab: the strip already carries the icon, the
      // label and the ×, so the panel's own header would duplicate all
      // three directly underneath.
      showHeader: false,
      strings: cxp_ui.CrossProbePanelStrings(
        title: l10n.crossProbePanelTitle,
        closeTooltip: l10n.crossProbeCloseTooltip,
        serverOffline: l10n.crossProbeServerOffline,
        peersSectionTitle: l10n.crossProbePanelPeersHeader,
        noPeers: l10n.crossProbePanelNoPeers,
        sendTooltip: l10n.crossProbeSendTooltip,
        unreachableSectionTitle: l10n.crossProbeUnreachableTitle,
        eventsSectionTitle: l10n.crossProbePanelEventsHeader,
        noEvents: l10n.crossProbePanelNoEvents,
        clearEventsLabel: l10n.crossProbeClearEvents,
        // The peer's reason arrives in the peer's own words; only the frame
        // around it is ours to translate.
        sendRejected: (peer, reason) => reason == null || reason.isEmpty
            ? l10n.crossProbeSendFailed(peer)
            : l10n.crossProbeSendRefused(peer, reason),
      ),
    );
  }
}

/// Adapts NetCrux's live CXP Riverpod state onto the app-agnostic
/// [cxp_ui.CrossProbePanelController] the shared panel renders against.
///
/// Bridges four reactive sources into the four [ValueListenable]s the panel
/// wraps in `ValueListenableBuilder`s — via `ref.listenManual(...,
/// fireImmediately: true)`:
///
/// * `cxpPeersProvider` (NetCrux's discovered [CxpPeerEntry]s) → foreign peers'
///   [PeerIdentity]s.
/// * `cxpEventLogProvider` (NetCrux's [CxpEventLogEntry]) mapped to the shared
///   [cxp_ui.CrossProbeEvent] superset — presence rows become the lifecycle
///   `peerConnected`/`peerDisconnected` kinds (null direction), the rest fold
///   `(kind, direction)` into the sent/received categories.
/// * `cxpDialFailuresProvider` → the unreachable-peers surface.
/// * `cxpServerHostProvider`'s running-ness → the offline banner.
///
/// and routes the panel's commands back into NetCrux: [onSendTo] resolves the
/// active tab's schematic selection through the same [resolveCxpSelection] the
/// automatic emitter uses and sends it to the chosen peer tagged with the
/// `crux.design_id` metadata; [onOpenPanel]/[onClose] toggle
/// `crossProbeVisibleProvider`; [onClearEvents] empties the event buffer.
///
/// Mounted inside the active tab's provider scope (the right pane of the
/// per-tab IDE layout), so `_ref` reads resolve this tab's
/// `selectedElementProvider` / `hierarchyTreeProvider` / `currentProjectProvider`
/// directly, while the root-scoped CXP providers resolve through the parent.
class NetCruxCrossProbePanelController
    implements cxp_ui.CrossProbePanelController {
  /// Creates a controller bound to [_ref] (the host widget's `ref`). Wires the
  /// reactive bridges immediately.
  NetCruxCrossProbePanelController(this._ref) {
    _peersSub = _ref.listenManual<AsyncValue<List<CxpPeerEntry>>>(
      cxpPeersProvider,
      (_, next) => _peers.value = _identities(next.value),
      fireImmediately: true,
    );
    _unreachableSub = _ref.listenManual<AsyncValue<List<CxpDialFailure>>>(
      cxpDialFailuresProvider,
      (_, next) => _unreachable.value = next.value ?? const <CxpDialFailure>[],
      fireImmediately: true,
    );
    _runningSub = _ref.listenManual<AsyncValue<NetcruxCxpServer?>>(
      cxpServerHostProvider,
      (_, next) => _serverRunning.value = next.value != null,
      fireImmediately: true,
    );
    _eventsSub = _ref.listenManual<List<CxpEventLogEntry>>(
      cxpEventLogProvider,
      (_, next) => _events.value = _toSharedEvents(next),
      fireImmediately: true,
    );
  }

  final WidgetRef _ref;

  final ValueNotifier<List<PeerIdentity>> _peers =
      ValueNotifier<List<PeerIdentity>>(const <PeerIdentity>[]);
  final ValueNotifier<List<cxp_ui.CrossProbeEvent>> _events =
      ValueNotifier<List<cxp_ui.CrossProbeEvent>>(
        const <cxp_ui.CrossProbeEvent>[],
      );
  final ValueNotifier<List<CxpDialFailure>> _unreachable =
      ValueNotifier<List<CxpDialFailure>>(const <CxpDialFailure>[]);
  final ValueNotifier<bool> _serverRunning = ValueNotifier<bool>(false);

  ProviderSubscription<AsyncValue<List<CxpPeerEntry>>>? _peersSub;
  ProviderSubscription<List<CxpEventLogEntry>>? _eventsSub;
  ProviderSubscription<AsyncValue<List<CxpDialFailure>>>? _unreachableSub;
  ProviderSubscription<AsyncValue<NetcruxCxpServer?>>? _runningSub;

  @override
  ValueListenable<List<PeerIdentity>> get peers => _peers;

  @override
  ValueListenable<List<cxp_ui.CrossProbeEvent>> get events => _events;

  @override
  ValueListenable<List<CxpDialFailure>> get unreachable => _unreachable;

  @override
  ValueListenable<bool> get serverRunning => _serverRunning;

  @override
  ValueListenable<cxp_ui.CrossProbeSendFailure?> get sendFailure =>
      _sendFailure;

  final ValueNotifier<cxp_ui.CrossProbeSendFailure?> _sendFailure =
      ValueNotifier<cxp_ui.CrossProbeSendFailure?>(null);

  @override
  void onSendTo(PeerIdentity peer) => unawaited(_sendTo(peer));

  /// Resolves the active tab's selection and sends it to [peer] as an
  /// ack-bearing `request_highlight`, then surfaces a rejected send as a
  /// panel toast — R8's "never a silent no-op". The automatic emitter still
  /// broadcasts fire-and-forget `notify_selection`; the explicit panel send is
  /// directed and wants confirmation, so it uses the acked form.
  ///
  /// Origination is a Pro capability, and this button is a route to it that
  /// ships in open core — so the tier is checked HERE, first, before the
  /// server or the selection is resolved. A denied press has already been
  /// explained by the gate; an empty selection after an admitted press is
  /// the existing quiet no-op, which is a different situation from a
  /// refusal.
  Future<void> _sendTo(PeerIdentity peer) async {
    if (!_ref.read(crossProbeOriginateGateProvider)(_ref.context)) return;
    final host = _ref.read(cxpServerHostProvider).value;
    if (host == null) return;
    final tree = _ref.read(hierarchyTreeProvider);
    final resolved = resolveCxpSelection(
      element: _ref.read(selectedElementProvider).primary,
      model: tree.model,
      scope: tree.selected,
    );
    if (resolved == null) return;
    final designId = cxpDesignIdForProject(_ref.read(currentProjectProvider));
    // Read before the ack wait: the exchange is logged and counted whether or
    // not the panel is still open when the ack lands. Both live at the app
    // root, so they outlive the panel.
    final eventLog = _ref.read(cxpEventLogProvider.notifier);
    final telemetry = _ref.read(telemetryServiceProvider);
    final result = await host.requestHighlight(
      peer.peerId,
      resolved.toRequestHighlight(<String, Object?>{
        cxpDesignIdMetadataKey: ?designId,
      }),
    );
    final ack = result.ack;
    if (result.delivered) {
      eventLog.recordOutbound(
        kind: CxpMessageKind.requestHighlight,
        peerLabel: '${peer.productName} (${peer.peerId})',
        detail: resolved.displayName,
      );
      // Past `delivered`, so a peer that was unreachable is an attempt, not a
      // cross-probe. A missing ack is a timeout — the peer never said yes, so
      // it counts as not honored, the same as an explicit refusal.
      telemetry.record(
        TelemetryEvent(
          'cxp.crossprobe',
          properties: <String, Object?>{
            'direction': 'outbound',
            'honored': ack?.honored ?? false,
          },
        ),
      );
    }
    // The ack wait runs up to five seconds, and the panel can close inside
    // it. Past that point `_ref` belongs to a disposed widget and the
    // failure notifier is disposed, so both would throw.
    if (_disposed) return;
    final peerLabel = peer.productName.isEmpty ? peer.peerId : peer.productName;
    if (!result.delivered) {
      // The peer disappeared between the panel rendering and the send — never
      // a silent no-op (R8). Surface it as a send failure so the user isn't
      // left staring at a panel that looks like it did nothing.
      _reportSendFailure(cxp_ui.CrossProbeSendFailure(peerLabel: peerLabel));
      return;
    }
    if (ack == null || !ack.honored) {
      _reportSendFailure(
        cxp_ui.CrossProbeSendFailure(peerLabel: peerLabel, reason: ack?.reason),
      );
    }
  }

  /// Publishes [failure] for the panel to toast. Failures compare by value,
  /// so one equal to the last would not notify the panel and a second failed
  /// send to the same peer would be silent; clearing first makes each count.
  void _reportSendFailure(cxp_ui.CrossProbeSendFailure failure) {
    _sendFailure
      ..value = null
      ..value = failure;
  }

  @override
  void onOpenPanel() {
    _ref.read(crossProbeVisibleProvider.notifier).set(visible: true);
    // Dock reveal: an inbound-attention open must surface the tab, not just
    // flip a flag behind the inspector.
    _ref.read(rightDockTabProvider.notifier).reveal(kRightDockTabCrossProbe);
  }

  @override
  void onClose() =>
      _ref.read(crossProbeVisibleProvider.notifier).set(visible: false);

  @override
  void onClearEvents() => _ref.read(cxpEventLogProvider.notifier).clear();

  /// Set by [dispose]. A send still awaiting its ack checks it before touching
  /// the widget's `ref` or the notifiers.
  bool _disposed = false;

  /// Releases the bridge subscriptions and backing notifiers.
  void dispose() {
    _disposed = true;
    _peersSub?.close();
    _eventsSub?.close();
    _unreachableSub?.close();
    _runningSub?.close();
    _peers.dispose();
    _events.dispose();
    _unreachable.dispose();
    _serverRunning.dispose();
    _sendFailure.dispose();
  }

  static List<PeerIdentity> _identities(List<CxpPeerEntry>? entries) =>
      <PeerIdentity>[
        for (final e in entries ?? const <CxpPeerEntry>[]) e.identity,
      ];

  /// Maps NetCrux's newest-first [CxpEventLogEntry] buffer onto the shared,
  /// richer [cxp_ui.CrossProbeEvent] list the panel renders — reversed to the
  /// oldest-first order the panel expects (it iterates in reverse for its
  /// newest-first display).
  static List<cxp_ui.CrossProbeEvent> _toSharedEvents(
    List<CxpEventLogEntry> entries,
  ) => <cxp_ui.CrossProbeEvent>[
    for (final e in entries.reversed) _toSharedEvent(e),
  ];

  static cxp_ui.CrossProbeEvent _toSharedEvent(CxpEventLogEntry e) {
    if (e.direction == CxpEventDirection.presence) {
      return e.kind == 'connected'
          ? cxp_ui.CrossProbeEvent.peerConnected(
              peerLabel: e.peerLabel,
              timestamp: e.timestamp,
            )
          : cxp_ui.CrossProbeEvent.peerDisconnected(
              peerLabel: e.peerLabel,
              timestamp: e.timestamp,
            );
    }
    final outbound = e.direction == CxpEventDirection.outbound;
    final direction = outbound
        ? cxp_ui.CrossProbeEventDirection.outbound
        : cxp_ui.CrossProbeEventDirection.inbound;
    final kind = switch (e.kind) {
      CxpMessageKind.notifySelection =>
        outbound
            ? cxp_ui.CrossProbeEventKind.selectionSent
            : cxp_ui.CrossProbeEventKind.selectionReceived,
      CxpMessageKind.requestHighlight =>
        outbound
            ? cxp_ui.CrossProbeEventKind.highlightSent
            : cxp_ui.CrossProbeEventKind.highlightReceived,
      CxpMessageKind.requestOpenArtifact ||
      CxpMessageKind.requestOpenArtifactAck =>
        cxp_ui.CrossProbeEventKind.openArtifact,
      _ => cxp_ui.CrossProbeEventKind.other,
    };
    return cxp_ui.CrossProbeEvent(
      kind: kind,
      direction: direction,
      peerLabel: e.peerLabel,
      timestamp: e.timestamp,
      summary: e.detail,
      messageKind: e.kind,
    );
  }
}
