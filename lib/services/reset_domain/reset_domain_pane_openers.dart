// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens / focuses the Reset Domain Analysis pane.
///
/// Default is a no-op so [NetcruxAction.showResetDomainAnalysisPane]
/// remains discoverable in the command palette / menu bar on
/// open-core builds. The Pro overlay overrides this with a
/// callback that mounts the panel through the workspace's docking
/// infrastructure.
typedef ShowResetDomainAnalysisPaneOpener =
    void Function(
      BuildContext context,
    );

/// Runs full-design reset domain analysis via
/// [ResetDomainAnalysisService.analyze], routes the result into the
/// per-tab `resetDomainAnalysisStateProvider`, and opens the panel.
/// The Pro overlay's opener also surfaces a progress indicator during
/// the walk.
///
/// Default is a no-op.
typedef RunResetDomainAnalysisOpener =
    void Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Scopes the Reset Domain panel to crossings involving the
/// right-clicked (or command-palette dispatched) signal. The Pro
/// overlay's opener reads the active per-tab schematic selection when
/// no explicit [signalPath] is supplied (command-palette path), or
/// accepts the path directly (schematic context-menu path), invokes
/// `ResetDomainAnalysisService.crossingsForSignal`, surfaces the
/// matching crossing through the per-tab
/// `resetDomainAnalysisStateProvider`, and opens the panel.
typedef ShowResetCrossingForSelectedSignalOpener =
    void Function(
      BuildContext context,
      WidgetRef ref, {
      String? signalPath,
      ElementId? signalId,
    });

/// Clears the Reset Domain pane's currently-focused crossing + domain
/// and dismisses any open detail sub-panels. The Pro overlay's opener
/// clears the per-tab `resetDomainAnalysisStateProvider`; open-core's
/// no-op is fine to invoke because there is nothing to clear.
typedef ClearResetAnalysisSelectionOpener =
    void Function(
      BuildContext context,
    );

/// Open-core extension point for showing the Reset Domain analysis
/// pane.
final showResetDomainAnalysisPaneOpenerProvider =
    Provider<ShowResetDomainAnalysisPaneOpener>(
      (_) => (_) {
        // Open-core no-op. Pro overlay overrides this with a callback
        // that mounts the Reset Domain analysis panel.
      },
      name: 'showResetDomainAnalysisPaneOpenerProvider',
    );

/// Open-core extension point for running full-design reset domain
/// analysis.
final runResetDomainAnalysisOpenerProvider =
    Provider<RunResetDomainAnalysisOpener>(
      (_) => (_, _) {
        // Open-core no-op. Pro overlay overrides this.
      },
      name: 'runResetDomainAnalysisOpenerProvider',
    );

/// Open-core extension point for the schematic context-menu
/// "Show Reset Crossings for This Signal" entry.
final showResetCrossingForSelectedSignalOpenerProvider =
    Provider<ShowResetCrossingForSelectedSignalOpener>(
      (_) => (_, _, {signalPath, signalId}) {
        // Open-core no-op. Pro overlay overrides this.
      },
      name: 'showResetCrossingForSelectedSignalOpenerProvider',
    );

/// Open-core extension point for clearing the active reset analysis
/// selection.
final clearResetAnalysisSelectionOpenerProvider =
    Provider<ClearResetAnalysisSelectionOpener>(
      (_) => (_) {
        // Open-core no-op — clearing is never gated and there is nothing
        // to clear when no analysis has ever been run. Pro overlay
        // overrides with a real dismissal path that clears the per-tab
        // notifier.
      },
      name: 'clearResetAnalysisSelectionOpenerProvider',
    );
