// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/core/policy/org_cross_probe_allowlist.dart';
import 'package:netcrux/features/remote/providers/cxp_inbound_handler_holder_provider.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';

/// What NetCrux binds into the shared CXP lifecycle in the root scope.
///
/// Listed with the root overrides every host of the app installs
/// (`netcruxAppOverrides`), so anything that mounts the root widget, the widget
/// tests included, has CXP bound. The settings loaded before `runApp` are bound
/// by `bootstrap`, which is the one place that loads them.
final List<Override> netcruxCxpOverrides = <Override>[
  // Who NetCrux is on CXP.
  cruxCxpProductBindingProvider.overrideWithValue(kNetcruxCxpBinding),
  // What NetCrux does when a peer asks: the handler the mounted workspace
  // publishes, so it can act on the active tab. Until one is mounted, every
  // request is acknowledged as unsupported.
  cruxCxpRequestHandlerProvider.overrideWith(
    (ref) =>
        ref.watch(netcruxInboundHandlerHolderProvider) ??
        const CruxCxpRequestHandler(),
  ),
  // The running build's version, from the same build info the About dialog
  // shows, so the Pro overlay reports its own. No compatibility logic reads
  // it, so a platform that cannot report one gets `dev` rather than a server
  // that fails to start.
  cruxCxpProductVersionProvider.overrideWith((ref) async {
    try {
      return (await ref.watch(aboutBuildInfoProvider.future)).version;
    } on Object {
      return 'dev';
    }
  }),
  // A dock bounce or taskbar flash, when a request was honoured and the user
  // has the setting on. It never steals focus.
  cruxCxpAttentionRequesterProvider.overrideWithValue(requestUserAttention),
  // The organization's allowlist, if it set one. Every cross-probe surface
  // (the panel, the badge, the menus, the buttons) reads the one filtered
  // list, so filtering once is filtering everywhere. Dropped rather than
  // greyed: an allowlist is a restriction, and a disabled entry naming a
  // machine an engineer may not reach tells them something the administrator
  // chose not to.
  cruxCxpPeerFilterProvider.overrideWith((ref) {
    final allowlist = ref.watch(orgCrossProbeAllowlistProvider);
    return (peer) => crossProbeAllowed(allowlist, peer.productName);
  }),
  // The outbound cross-probe count (the suite network-effect funnel), recorded
  // once for every surface that sends. A send that ended before anything left
  // (nothing selected, a denial, the server off, no peer running) is not
  // counted. A cross-probe the peer could not act on counts as not honoured,
  // which is the failure the funnel exists to surface.
  crossProbeSendObserverProvider.overrideWith(
    (ref) =>
        (record) => recordCrossProbeSend(ref.read, record),
  ),
];

/// Counts one outbound cross-probe (`cxp.crossprobe`, direction `outbound`),
/// from whichever surface sent it.
///
/// A send that ended before anything left (nothing selected, a denial, the
/// server off, no peer running) is not counted. A cross-probe the peer could
/// not act on counts as not honoured, which is the failure the funnel exists
/// to surface. Public so a build that observes the same sends for another
/// purpose (an audit line) records the count the same way.
void recordCrossProbeSend(CruxCxpReader read, CrossProbeSendRecord record) {
  if (!_leftTheMachine(record.outcome.kind)) return;
  read(telemetryServiceProvider).record(
    TelemetryEvent(
      'cxp.crossprobe',
      properties: <String, Object?>{
        'direction': 'outbound',
        'honored': record.outcome.kind == CrossProbeOutcomeKind.sent,
      },
    ),
  );
}

/// Whether a send of this outcome was an attempt to reach a peer: every
/// outcome but the four that ended before anything was sent.
bool _leftTheMachine(CrossProbeOutcomeKind kind) => switch (kind) {
  CrossProbeOutcomeKind.denied ||
  CrossProbeOutcomeKind.nothingSelected ||
  CrossProbeOutcomeKind.serverOff ||
  CrossProbeOutcomeKind.noPeers => false,
  _ => true,
};
