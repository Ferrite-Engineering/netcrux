// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens / focuses the FSM Bubble Diagram pane.
///
/// Default is a no-op so [NetcruxAction.showFsmBubbleDiagram] remains
/// discoverable in the command palette / menu bar on open-core builds.
/// The Pro overlay overrides this with a callback that
/// mounts the panel through the workspace's docking infrastructure.
typedef ShowFsmBubbleDiagramOpener = void Function(BuildContext context);

/// Forces structural FSM detection for the right-clicked (or
/// command-palette dispatched) register. The Pro overlay's opener
/// reads the active per-tab schematic selection when no explicit
/// [stateRegisterId] is supplied (command-palette path), or accepts
/// the id directly (schematic context-menu path), invokes
/// `FsmDetectionService.detectAt`, surfaces the result through the
/// per-tab `selectedFsmProvider`, and opens the bubble diagram panel.
///
/// On detection failure the opener surfaces an
/// [UnimplementedFsmDetection]-derived snackbar but never throws.
typedef DetectFsmForCurrentRegisterOpener =
    void Function(
      BuildContext context,
      WidgetRef ref, {
      ElementId? stateRegisterId,
    });

/// Runs full-design FSM detection through
/// `FsmDetectionService.detect` and opens the detection-results
/// dialog. The Pro overlay's opener surfaces a progress indicator
/// during the walk and routes the result into the per-tab cache.
///
/// Default is a no-op.
typedef RunFsmDetectionAcrossDesignOpener =
    void Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Clears the currently-focused FSM and dismisses the bubble diagram
/// panel. The Pro overlay's opener clears the per-tab
/// `selectedFsmProvider` and unmounts the panel; open-core's no-op is
/// fine to invoke because there is nothing to clear.
typedef ClearFsmSelectionOpener = void Function(BuildContext context);

/// Open-core extension point for showing the FSM bubble diagram pane.
final showFsmBubbleDiagramOpenerProvider = Provider<ShowFsmBubbleDiagramOpener>(
  (_) => (_) {
    // Open-core no-op. The Pro overlay overrides this with a callback
    // that mounts the bubble diagram panel.
  },
  name: 'showFsmBubbleDiagramOpenerProvider',
);

/// Open-core extension point for forcing FSM detection on the current
/// register.
final detectFsmForCurrentRegisterOpenerProvider =
    Provider<DetectFsmForCurrentRegisterOpener>(
      (_) => (_, _, {stateRegisterId}) {
        // Open-core no-op. The Pro overlay overrides this.
      },
      name: 'detectFsmForCurrentRegisterOpenerProvider',
    );

/// Open-core extension point for full-design FSM detection.
final runFsmDetectionAcrossDesignOpenerProvider =
    Provider<RunFsmDetectionAcrossDesignOpener>(
      (_) => (_, _) {
        // Open-core no-op. The Pro overlay overrides this.
      },
      name: 'runFsmDetectionAcrossDesignOpenerProvider',
    );

/// Open-core extension point for clearing the active FSM selection.
final clearFsmSelectionOpenerProvider = Provider<ClearFsmSelectionOpener>(
  (_) => (_) {
    // Open-core no-op — clearing is never gated and there is nothing
    // to clear when no FSM has ever been selected. Pro overlay
    // overrides with a real dismissal path.
  },
  name: 'clearFsmSelectionOpenerProvider',
);
