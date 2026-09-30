// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens / focuses the Netlist Diff View pane.
///
/// Default is a no-op so [NetcruxAction.showDiffPane] remains
/// discoverable in the command palette / menu bar on open-core
/// builds. The Pro overlay overrides this with a callback
/// that mounts the panel through the workspace's docking
/// infrastructure.
typedef ShowDiffPaneOpener = void Function(BuildContext context);

/// Prompts the user to choose a comparison-side netlist file (via
/// platform file picker) and starts a diff against the baseline.
///
/// Default is a no-op. The Pro overlay overrides with a callback
/// that:
///
///   1. Opens the platform file picker for accepted netlist source
///      types (matching the open-core elaboration loader's accepted
///      extensions),
///   2. Reads the selection as the comparison-side [NetlistRef],
///      builds a [NetlistDiffRequest] against the current baseline,
///      dispatches it through the active per-tab `diffPaneStateProvider`,
///   3. Surfaces a snackbar on load failure or completion.
typedef LoadComparisonNetlistOpener =
    void Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Clears any active comparison and unmounts the Diff View pane.
///
/// Default is a no-op. The Pro overlay overrides with a callback
/// that clears the per-tab `diffPaneStateProvider` notifier and
/// dismisses the panel.
typedef ClearComparisonNetlistOpener = void Function(BuildContext context);

/// Jumps the panel selection to the next [ElementChange] in the
/// active diff (wraps after the last). The Pro overlay's opener
/// reads the active tab's diff state, advances the
/// `selectedChange` cursor, and ensures the panel is visible.
typedef NavigateNextDiffOpener = void Function(BuildContext context);

/// Jumps the panel selection to the previous [ElementChange] in the
/// active diff (wraps before the first).
typedef NavigatePrevDiffOpener = void Function(BuildContext context);

/// Open-core extension point for showing the Diff View pane.
final showDiffPaneOpenerProvider = Provider<ShowDiffPaneOpener>(
  (_) => (_) {
    // Open-core no-op. The Pro overlay overrides this with a callback
    // that mounts the diff pane.
  },
  name: 'showDiffPaneOpenerProvider',
);

/// Open-core extension point for loading a comparison-side netlist
/// via the platform file picker.
final loadComparisonNetlistOpenerProvider =
    Provider<LoadComparisonNetlistOpener>(
      (_) => (_, _) {
        // Open-core no-op. The Pro overlay overrides this.
      },
      name: 'loadComparisonNetlistOpenerProvider',
    );

/// Open-core extension point for clearing the active comparison.
final clearComparisonNetlistOpenerProvider =
    Provider<ClearComparisonNetlistOpener>(
      (_) => (_) {
        // Open-core no-op. The Pro overlay overrides this.
      },
      name: 'clearComparisonNetlistOpenerProvider',
    );

/// Open-core extension point for "navigate next diff" dispatch.
final navigateNextDiffOpenerProvider = Provider<NavigateNextDiffOpener>(
  (_) => (_) {
    // Open-core no-op. The Pro overlay overrides this.
  },
  name: 'navigateNextDiffOpenerProvider',
);

/// Open-core extension point for "navigate previous diff" dispatch.
final navigatePrevDiffOpenerProvider = Provider<NavigatePrevDiffOpener>(
  (_) => (_) {
    // Open-core no-op. The Pro overlay overrides this.
  },
  name: 'navigatePrevDiffOpenerProvider',
);
