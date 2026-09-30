// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens / focuses the CDC Analysis pane.
///
/// Default is a no-op so [NetcruxAction.showCdcAnalysisPane] remains
/// discoverable in the command palette / menu bar on open-core builds.
/// The Pro overlay overrides this with a callback that
/// mounts the panel through the workspace's docking infrastructure.
typedef ShowCdcAnalysisPaneOpener = void Function(BuildContext context);

/// Runs full-design CDC analysis via
/// [ClockDomainAnalysisService.analyze], routes the result into the
/// per-tab `cdcAnalysisStateProvider`, and opens the CDC analysis
/// panel. The Pro overlay's opener also surfaces a progress
/// indicator during the walk.
///
/// Default is a no-op.
typedef RunCdcAnalysisOpener =
    void Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Scopes the CDC panel to crossings involving the right-clicked (or
/// command-palette dispatched) signal. The Pro overlay's opener reads
/// the active per-tab schematic selection when no explicit
/// [signalPath] is supplied (command-palette path), or accepts the
/// path directly (schematic context-menu path), invokes
/// `ClockDomainAnalysisService.crossingsForSignal`, surfaces the
/// matching crossing through the per-tab `cdcAnalysisStateProvider`,
/// and opens the CDC analysis panel.
typedef ShowCdcCrossingForSelectedSignalOpener =
    void Function(
      BuildContext context,
      WidgetRef ref, {
      String? signalPath,
      ElementId? signalId,
    });

/// Clears the CDC pane's currently-focused crossing + domain and
/// dismisses any open detail sub-panels. The Pro overlay's opener
/// clears the per-tab `cdcAnalysisStateProvider`; open-core's no-op
/// is fine to invoke because there is nothing to clear.
typedef ClearCdcAnalysisSelectionOpener = void Function(BuildContext context);

/// Open-core extension point for showing the CDC analysis pane.
final showCdcAnalysisPaneOpenerProvider = Provider<ShowCdcAnalysisPaneOpener>(
  (_) => (_) {
    // Open-core no-op. Pro overlay overrides this with a callback
    // that mounts the CDC analysis panel.
  },
  name: 'showCdcAnalysisPaneOpenerProvider',
);

/// Open-core extension point for running full-design CDC analysis.
final runCdcAnalysisOpenerProvider = Provider<RunCdcAnalysisOpener>(
  (_) => (_, _) {
    // Open-core no-op. Pro overlay overrides this.
  },
  name: 'runCdcAnalysisOpenerProvider',
);

/// Open-core extension point for the schematic context-menu
/// "Show CDC Crossings for This Signal" entry.
final showCdcCrossingForSelectedSignalOpenerProvider =
    Provider<ShowCdcCrossingForSelectedSignalOpener>(
      (_) => (_, _, {signalPath, signalId}) {
        // Open-core no-op. Pro overlay overrides this.
      },
      name: 'showCdcCrossingForSelectedSignalOpenerProvider',
    );

/// Open-core extension point for clearing the active CDC selection.
final clearCdcAnalysisSelectionOpenerProvider =
    Provider<ClearCdcAnalysisSelectionOpener>(
      (_) => (_) {
        // Open-core no-op — clearing is never gated and there is nothing
        // to clear when no analysis has ever been run. Pro overlay
        // overrides with a real dismissal path that clears the per-tab
        // notifier.
      },
      name: 'clearCdcAnalysisSelectionOpenerProvider',
    );
