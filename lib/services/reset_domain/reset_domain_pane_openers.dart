// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';

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

/// Scopes the Reset Domain panel to the crossings a signal takes part in.
///
/// [target] is the schematic element the request is about: the
/// right-clicked element on the context-menu path. With no [target] and
/// no [signalPath] (the command-palette path) the Pro overlay's opener
/// falls back to the active tab's schematic selection. [signalPath] /
/// [signalId] name a signal directly instead, matched against the
/// crossings' signal names.
///
/// The Pro overlay's opener reuses the tab's analysis result when it is
/// current for the loaded design and runs the analysis otherwise, filters
/// the panel to the matching crossings through the per-tab
/// `resetDomainAnalysisStateProvider` when there are several, focuses and
/// reveals one, and opens the panel; it reports through a snackbar when
/// the signal takes part in no crossing.
typedef ShowResetCrossingForSelectedSignalOpener =
    void Function(
      BuildContext context,
      WidgetRef ref, {
      String? signalPath,
      ElementId? signalId,
      SelectedElement? target,
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
      (_) => (_, _, {signalPath, signalId, target}) {
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
