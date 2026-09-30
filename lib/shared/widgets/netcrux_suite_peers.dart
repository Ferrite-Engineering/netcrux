// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:netcrux/core/help_urls.dart';
import 'package:netcrux/core/netcrux_url_launcher.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// The "More from EDACrux" rows, wired to NetCrux's own landing path.
///
/// The blurbs are NetCrux's: they say what each other tool does for someone
/// reading a schematic, which is not what it does for someone holding a
/// waveform. See the `emptyCanvasPeer*` ARB descriptions.
///
/// A widget rather than a helper for the same reason [NetCruxSuiteFooter] is
/// one — both start screens, desktop and browser, render it, and the wording
/// and the landing path must not drift between them.
class NetCruxSuitePeers extends StatelessWidget {
  /// Creates the peers section.
  const NetCruxSuitePeers({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return CruxSuitePeers(
      heading: l10n.emptyCanvasPeersHeading,
      entries: [
        CruxSuitePeerEntry(
          product: CruxSuiteProduct.waveCrux,
          blurb: l10n.emptyCanvasPeerWaveCrux,
        ),
        CruxSuitePeerEntry(
          product: CruxSuiteProduct.lintCrux,
          blurb: l10n.emptyCanvasPeerLintCrux,
        ),
        CruxSuitePeerEntry(
          product: CruxSuiteProduct.simCrux,
          blurb: l10n.emptyCanvasPeerSimCrux,
        ),
      ],
      onOpenPeer: (peer) =>
          unawaited(netcruxLaunchUrl(Uri.parse(HelpUrls.suitePeer(peer.slug)))),
    );
  }
}
