// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/glowing_app_icon.dart';
import 'package:netcrux/shared/widgets/netcrux_suite_footer.dart';
import 'package:netcrux/shared/widgets/netcrux_suite_peers.dart';

/// The browser build's start screen: the same shell as the desktop
/// `EmptyCanvasContent`, with the one thing a browser can open.
///
/// The desktop start screen offers projects, HDL sources, workspaces and the
/// recents behind them — every one a local path, and HDL needs Yosys. In the
/// browser those buttons could only fail, so this variant offers a Yosys
/// JSON netlist and says what the desktop app is for.
class BrowserEmptyCanvasContent extends ConsumerWidget {
  /// Creates the browser start screen.
  const BrowserEmptyCanvasContent({required this.onOpenNetlistJson, super.key});

  /// Fired when the Open Netlist JSON button is tapped.
  final VoidCallback onOpenNetlistJson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final version = ref.watch(aboutBuildInfoProvider).value?.version;
    return EmptyCanvasState(
      header: const GlowingAppIcon(size: 72),
      title: l10n.emptyCanvasTitle,
      subtitle: l10n.emptyCanvasSubtitle,
      versionLabel: version == null ? null : l10n.emptyCanvasVersion(version),
      recentFilesSection: Text(
        l10n.emptyCanvasBrowserHint,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      primaryActions: <Widget>[
        FilledButton.icon(
          onPressed: onOpenNetlistJson,
          icon: const Icon(Icons.data_object),
          label: Text(l10n.actionOpenNetlistJson),
        ),
      ],
      // The browser build is where this line earns the most: a visitor
      // trying the web viewer has installed nothing yet.
      // What the other three products do for someone who is here. The
      // browser build is where this earns the most: a visitor trying the
      // web viewer has installed nothing yet.
      peers: const NetCruxSuitePeers(),
      footer: const NetCruxSuiteFooter(),
    );
  }
}
