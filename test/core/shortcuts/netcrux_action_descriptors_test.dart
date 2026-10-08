// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/license/netcrux_gated_feature.dart';
import 'package:netcrux/core/shortcuts/action_category.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptor.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptors.dart';

/// Contract tests for the descriptor table — the single source of truth
/// for surface membership and enablement. The per-surface rendering
/// conformance lives in `action_surface_conformance_test.dart`; this file
/// pins the table's own invariants, including the assertions migrated
/// from the deleted per-surface hidden-action sets.
void main() {
  const empty = NetcruxActionContext();
  const loaded = NetcruxActionContext(
    hasOpenTab: true,
    hasNetlist: true,
    hasSelection: true,
    hasTraceOverlay: true,
    hasXTraceResult: true,
    comparisonActive: true,
    waveformLoaded: true,
    cdcAnalysisPresent: true,
    resetAnalysisPresent: true,
    fsmFocused: true,
    activityColoringActive: true,
    paneCount: 2,
    // Two tabs in the active pane, so Next / Previous Tab are live too.
    tabCountInActivePane: 2,
  );

  group('command-palette reachability', () {
    test('openCommandPalette is reachable from the menu (recovery path)', () {
      // Must appear in the menu bar so unbinding Cmd/Ctrl+Shift+P can never
      // make the palette permanently inaccessible.
      expect(
        isActionVisibleIn(
          NetcruxAction.openCommandPalette,
          NetcruxActionSurface.menu,
          empty,
        ),
        isTrue,
      );
      expect(
        isActionEnabled(NetcruxAction.openCommandPalette, empty),
        isTrue,
        reason: 'the recovery path must work on the empty canvas too',
      );
    });

    test('openCommandPalette is excluded from the palette itself', () {
      // Self-referential — you can't open the palette from the palette.
      expect(
        paletteActionsFor(loaded),
        isNot(contains(NetcruxAction.openCommandPalette)),
      );
    });

    test('openCommandPalette is grouped under View in the menu', () {
      expect(
        // VS Code lists the palette opener at the top of View, and the
        // suite menus follow it.
        groupedActionsFor(
          NetcruxActionSurface.menu,
          empty,
        )[ActionCategory.view],
        contains(NetcruxAction.openCommandPalette),
      );
    });
  });

  group('X-trace actions are reachable now the result panel ships', () {
    // The inverse of what this group asserted before `XTraceResultPanel`
    // landed: both openers were surfaceless because the
    // Pro back-cone walk had nowhere to show its output. The panel exists,
    // so hiding them would now be the bug — and the assertion is written
    // positively rather than deleted, so emptying either surface set fails
    // here as well as in the reachability guard.
    const openers = <NetcruxAction>[
      NetcruxAction.showXTrace,
      NetcruxAction.showXTracePanel,
    ];

    test('showXTrace + showXTracePanel reach the menu and the palette', () {
      for (final action in openers) {
        expect(
          isActionVisibleIn(action, NetcruxActionSurface.menu, loaded),
          isTrue,
          reason: '$action must appear in the menu bar',
        );
        expect(
          isActionVisibleIn(action, NetcruxActionSurface.palette, loaded),
          isTrue,
          reason: '$action must appear in the command palette',
        );
      }
    });

    test('neither opener claims the toolbar', () {
      // The toolbar is tier-1 actions only; cone-of-influence — the closest
      // analogue and the group X-trace sits beside — is menu+palette too.
      for (final action in openers) {
        expect(
          isActionVisibleIn(action, NetcruxActionSurface.toolbar, loaded),
          isFalse,
          reason: '$action is not a tier-1 toolbar action',
        );
      }
    });

    test('showXTrace needs a selection; showXTracePanel needs only a tab', () {
      // The panel opens on its empty state with nothing selected — that is
      // what its empty string is written for — while the walk has nothing to
      // radiate from.
      expect(isActionEnabled(NetcruxAction.showXTrace, empty), isFalse);
      expect(isActionEnabled(NetcruxAction.showXTracePanel, empty), isFalse);
      expect(
        isActionEnabled(
          NetcruxAction.showXTracePanel,
          const NetcruxActionContext(hasOpenTab: true),
        ),
        isTrue,
      );
      expect(
        isActionEnabled(
          NetcruxAction.showXTrace,
          const NetcruxActionContext(hasOpenTab: true),
        ),
        isFalse,
      );
    });

    test('clearXTrace stays discoverable (clearing is never hidden)', () {
      expect(paletteActionsFor(loaded), contains(NetcruxAction.clearXTrace));
      expect(
        isActionVisibleIn(
          NetcruxAction.clearXTrace,
          NetcruxActionSurface.menu,
          loaded,
        ),
        isTrue,
      );
    });
  });

  group('empty-workspace enablement walk', () {
    test('context-dependent actions are disabled with zero tabs open', () {
      // The concrete set that used to be enabled-but-inert on the empty
      // canvas: viewport navigation, exports, sessions, pane management,
      // and every Pro opener that targets the active tab.
      const contextDependent = <NetcruxAction>[
        NetcruxAction.zoomIn,
        NetcruxAction.zoomOut,
        NetcruxAction.zoomFitAll,
        NetcruxAction.zoomToSelection,
        NetcruxAction.jumpToTop,
        NetcruxAction.popOutScope,
        NetcruxAction.openSearch,
        NetcruxAction.exportPng,
        NetcruxAction.exportSvg,
        NetcruxAction.exportJson,
        NetcruxAction.saveSession,
        NetcruxAction.openSession,
        NetcruxAction.closeProject,
        NetcruxAction.splitPaneRight,
        NetcruxAction.closePane,
        NetcruxAction.focusOtherPane,
        NetcruxAction.moveTabToOtherPane,
        NetcruxAction.showFanin,
        NetcruxAction.showFanout,
        NetcruxAction.showConeOfInfluenceFanin,
        NetcruxAction.showConeOfInfluenceFanout,
        NetcruxAction.runCdcAnalysis,
        NetcruxAction.runResetDomainAnalysis,
        NetcruxAction.runFsmDetectionAcrossDesign,
        NetcruxAction.runActivityAnalysis,
        NetcruxAction.loadComparisonNetlist,
        NetcruxAction.navigateNextDiff,
        NetcruxAction.navigatePrevDiff,
        NetcruxAction.openWaveformFile,
        NetcruxAction.closeWaveformFile,
        NetcruxAction.showDiffPane,
        NetcruxAction.showCdcAnalysisPane,
        NetcruxAction.showResetDomainAnalysisPane,
        NetcruxAction.showFsmBubbleDiagram,
        NetcruxAction.showActivityHeatmap,
        NetcruxAction.addBookmark,
        NetcruxAction.addAnnotation,
        NetcruxAction.openSourceForElement,
        NetcruxAction.clearOverlay,
        NetcruxAction.clearConeOfInfluence,
        NetcruxAction.clearXTrace,
        NetcruxAction.clearFsmSelection,
        NetcruxAction.clearCdcAnalysisSelection,
        NetcruxAction.clearResetAnalysisSelection,
        NetcruxAction.clearActivityColoring,
        NetcruxAction.clearComparisonNetlist,
      ];
      for (final action in contextDependent) {
        expect(
          isActionEnabled(action, empty),
          isFalse,
          reason: '$action must grey out on the empty canvas',
        );
      }
    });

    test('workspace-independent actions stay enabled with zero tabs', () {
      const alwaysAvailable = <NetcruxAction>[
        NetcruxAction.openProject,
        NetcruxAction.openSourceFiles,
        NetcruxAction.importFilelist,
        NetcruxAction.openCommandPalette,
        NetcruxAction.openSettings,
        NetcruxAction.openAbout,
        NetcruxAction.showCrossProbePanel,
        NetcruxAction.openSymbolManager,
        NetcruxAction.importSymbolFromSvg,
        NetcruxAction.quit,
      ];
      for (final action in alwaysAvailable) {
        expect(
          isActionEnabled(action, empty),
          isTrue,
          reason: '$action must stay available on the empty canvas',
        );
      }
    });

    test('selection-seeded actions need a selection, not just a design', () {
      const selectionSeeded = <NetcruxAction>[
        NetcruxAction.showFanin,
        NetcruxAction.showFanout,
        NetcruxAction.showConeOfInfluenceFanin,
        NetcruxAction.showConeOfInfluenceFanout,
        NetcruxAction.showXTrace,
        NetcruxAction.addBookmark,
        NetcruxAction.addAnnotation,
        NetcruxAction.openSourceForElement,
        NetcruxAction.editSymbolForCurrentInstance,
        NetcruxAction.removeSymbolForCurrentInstance,
        NetcruxAction.detectFsmForCurrentRegister,
        NetcruxAction.showCdcCrossingForSelectedSignal,
        NetcruxAction.showResetCrossingForSelectedSignal,
      ];
      const designNoSelection = NetcruxActionContext(
        hasOpenTab: true,
        hasNetlist: true,
      );
      const withSelection = NetcruxActionContext(
        hasOpenTab: true,
        hasNetlist: true,
        hasSelection: true,
      );
      for (final action in selectionSeeded) {
        expect(
          isActionEnabled(action, designNoSelection),
          isFalse,
          reason: '$action must grey out with nothing selected',
        );
        expect(
          isActionEnabled(action, withSelection),
          isTrue,
          reason: '$action must enable once something is selected',
        );
      }
    });

    test('everything is enabled in the fully-loaded split-pane context', () {
      for (final action in NetcruxAction.values) {
        if (action == NetcruxAction.splitPaneRight) continue;
        // Leave Session is gated on a live collaborative session, which the
        // workspace context does not model; its own group covers it.
        if (action == NetcruxAction.leaveSession) continue;
        expect(
          isActionEnabled(action, loaded),
          isTrue,
          reason: '$action should be enabled with everything loaded',
        );
      }
      // Split is the one action gated on NOT being split already.
      expect(isActionEnabled(NetcruxAction.splitPaneRight, loaded), isFalse);
    });
  });

  group('table invariants', () {
    test('every action is surfaced somewhere', () {
      // No exceptions. The two X-trace openers were the only entries this
      // set ever held, and they were held for exactly as long as their
      // result panel did not exist; `XTraceResultPanel` shipped, so the
      // carve-out is gone rather than narrowed. Re-introducing one is a
      // deliberate decision that belongs in `_allowedSurfaceless` in
      // test/static/action_reachability_guard_test.dart, with its reason —
      // that guard is the one designed to hold such an allowance.
      for (final action in NetcruxAction.values) {
        expect(
          descriptorFor(action).surfaces,
          isNotEmpty,
          reason: '$action must be discoverable from at least one surface',
        );
      }
    });

    test('toolbar membership is the curated open-core set', () {
      final toolbarActions = NetcruxAction.values
          .where(
            (a) => descriptorFor(
              a,
            ).surfaces.contains(NetcruxActionSurface.toolbar),
          )
          .toSet();
      expect(toolbarActions, <NetcruxAction>{
        // ── the canonical common block, identical in all four products ──
        // Open · Save · Close │ Search · Cross-Probe · Settings.
        NetcruxAction.openProject,
        NetcruxAction.saveSession,
        NetcruxAction.closeProject,
        NetcruxAction.openSearch,
        NetcruxAction.showCrossProbePanel,
        NetcruxAction.openSettings,
        // ── NetCrux's own block ─────────────────────────────────────────
        NetcruxAction.openSourceFiles,
        NetcruxAction.openNetlistJson,
        NetcruxAction.zoomIn,
        NetcruxAction.zoomOut,
        NetcruxAction.zoomFitAll,
        NetcruxAction.zoomToSelection,
        NetcruxAction.jumpToTop,
        NetcruxAction.popOutScope,
        // The trace trio shares one grouped (split) toolbar slot rather than
        // three near-identical buttons — they were menu-only before.
        NetcruxAction.showFanin,
        NetcruxAction.showFanout,
        NetcruxAction.clearOverlay,
      });
    });

    test('groupedActionsFor returns a key for every ActionCategory and '
        'groups by the action category', () {
      final grouped = groupedActionsFor(NetcruxActionSurface.menu, loaded);
      for (final cat in ActionCategory.values) {
        expect(grouped.containsKey(cat), isTrue);
      }
      for (final entry in grouped.entries) {
        for (final action in entry.value) {
          expect(action.category, entry.key);
        }
      }
    });

    test('the menu shows disabled actions; the palette omits them', () {
      // zoomIn is disabled in the empty context: still present in the
      // menu grouping (greyed), absent from the palette list.
      final menuActions = groupedActionsFor(
        NetcruxActionSurface.menu,
        empty,
      ).values.expand((a) => a);
      expect(menuActions, contains(NetcruxAction.zoomIn));
      expect(paletteActionsFor(empty), isNot(contains(NetcruxAction.zoomIn)));
    });
  });

  group('the browser build', () {
    const browser = NetcruxActionContext(
      hasOpenTab: true,
      hasNetlist: true,
      hasSelection: true,
      isBrowser: true,
    );

    /// Actions that need a local file system, a subprocess or a socket.
    const desktopOnly = <NetcruxAction>{
      NetcruxAction.openProject,
      NetcruxAction.openSourceFiles,
      NetcruxAction.openSession,
      NetcruxAction.saveSession,
      NetcruxAction.openWorkspace,
      NetcruxAction.saveWorkspaceAs,
      NetcruxAction.importFilelist,
      NetcruxAction.exportPng,
      NetcruxAction.exportSvg,
      NetcruxAction.exportJson,
      NetcruxAction.showCrossProbePanel,
      NetcruxAction.checkForUpdates,
      NetcruxAction.quit,
    };

    test('hides the desktop-only actions from every surface', () {
      for (final action in desktopOnly) {
        expect(isActionVisible(action, browser), isFalse, reason: '$action');
        expect(isActionVisible(action, loaded), isTrue, reason: '$action');
        expect(paletteActionsFor(browser), isNot(contains(action)));
        expect(
          groupedActionsFor(
            NetcruxActionSurface.menu,
            browser,
          ).values.expand((a) => a),
          isNot(contains(action)),
        );
      }
    });

    test('hides every Pro action: the browser build is Open Core only', () {
      for (final action in NetcruxAction.values) {
        if (action.requiredTier == LicenseTier.openCore) continue;
        expect(isActionVisible(action, browser), isFalse, reason: '$action');
      }
    });

    test('offers Open Netlist JSON on every surface, with no tab open', () {
      const noTab = NetcruxActionContext(isBrowser: true);
      for (final surface in NetcruxActionSurface.values) {
        expect(
          isActionVisibleIn(NetcruxAction.openNetlistJson, surface, noTab),
          isTrue,
          reason: '$surface',
        );
      }
      expect(isActionInvocable(NetcruxAction.openNetlistJson, noTab), isTrue);
    });

    test('keeps viewing and navigation', () {
      for (final action in const [
        NetcruxAction.openSearch,
        NetcruxAction.zoomFitAll,
        NetcruxAction.zoomToSelection,
        NetcruxAction.showFanin,
        NetcruxAction.openSettings,
        NetcruxAction.openCommandPalette,
      ]) {
        expect(isActionInvocable(action, browser), isTrue, reason: '$action');
      }
    });

    test('a hidden action is not invocable even when it would be enabled', () {
      expect(isActionEnabled(NetcruxAction.openProject, browser), isTrue);
      expect(isActionInvocable(NetcruxAction.openProject, browser), isFalse);
    });
  });

  group('zoomToSelection', () {
    test('is on the toolbar, the menu and the palette', () {
      expect(
        descriptorFor(NetcruxAction.zoomToSelection).surfaces,
        NetcruxActionSurface.values.toSet(),
      );
    });

    test('is in the Navigate category and is open core', () {
      expect(NetcruxAction.zoomToSelection.category, ActionCategory.navigate);
      expect(
        NetcruxAction.zoomToSelection.requiredTier,
        LicenseTier.openCore,
      );
      expect(NetcruxAction.zoomToSelection.gatedFeature, isNull);
    });

    test('is disabled until something is selected', () {
      const loaded = NetcruxActionContext(hasOpenTab: true, hasNetlist: true);
      expect(isActionEnabled(NetcruxAction.zoomToSelection, loaded), isFalse);
      const selected = NetcruxActionContext(
        hasOpenTab: true,
        hasNetlist: true,
        hasSelection: true,
      );
      expect(isActionEnabled(NetcruxAction.zoomToSelection, selected), isTrue);
    });
  });

  group('clearOverlay (Escape)', () {
    test('is enabled by a focused crossing alone', () {
      const loaded = NetcruxActionContext(hasOpenTab: true, hasNetlist: true);
      expect(isActionEnabled(NetcruxAction.clearOverlay, loaded), isFalse);
      const crossing = NetcruxActionContext(
        hasOpenTab: true,
        hasNetlist: true,
        hasCrossingSelection: true,
      );
      expect(isActionEnabled(NetcruxAction.clearOverlay, crossing), isTrue);
    });
  });

  group('collaborative sessions', () {
    const overlay = NetcruxActionContext(collaborationAvailable: true);
    const live = NetcruxActionContext(
      collaborationAvailable: true,
      inCollabSession: true,
    );

    test('Share, Join and Leave are File-menu and palette actions', () {
      for (final action in const [
        NetcruxAction.shareSession,
        NetcruxAction.joinSession,
        NetcruxAction.leaveSession,
      ]) {
        expect(action.category, ActionCategory.file, reason: '$action');
        expect(descriptorFor(action).surfaces, {
          NetcruxActionSurface.menu,
          NetcruxActionSurface.palette,
        });
      }
    });

    test('only hosting carries a tier, and only it can report a denial', () {
      expect(NetcruxAction.shareSession.requiredTier, LicenseTier.enterprise);
      expect(
        NetcruxAction.shareSession.gatedFeature,
        NetcruxGatedFeature.collaboration,
      );
      for (final free in const [
        NetcruxAction.joinSession,
        NetcruxAction.leaveSession,
      ]) {
        expect(free.requiredTier, LicenseTier.openCore, reason: '$free');
        expect(free.gatedFeature, isNull, reason: '$free');
      }
    });

    test('Join and Leave exist only where a session can actually run', () {
      // The open-source build binds the no-op service, so a free, unbadged
      // Join would do nothing there.
      for (final action in const [
        NetcruxAction.joinSession,
        NetcruxAction.leaveSession,
      ]) {
        expect(isActionVisible(action, empty), isFalse, reason: '$action');
        expect(isActionVisible(action, overlay), isTrue, reason: '$action');
        expect(
          isActionVisible(
            action,
            const NetcruxActionContext(
              collaborationAvailable: true,
              isBrowser: true,
            ),
          ),
          isFalse,
          reason: '$action',
        );
      }
      // Share stays discoverable and badged in a desktop open-core build,
      // where activating it says the feature needs NetCrux Pro.
      expect(isActionVisible(NetcruxAction.shareSession, empty), isTrue);
    });

    test('Share and Join grey out in a session; Leave only works in one', () {
      expect(isActionEnabled(NetcruxAction.shareSession, overlay), isTrue);
      expect(isActionEnabled(NetcruxAction.joinSession, overlay), isTrue);
      expect(isActionEnabled(NetcruxAction.leaveSession, overlay), isFalse);

      expect(isActionEnabled(NetcruxAction.shareSession, live), isFalse);
      expect(isActionEnabled(NetcruxAction.joinSession, live), isFalse);
      expect(isActionEnabled(NetcruxAction.leaveSession, live), isTrue);

      expect(paletteActionsFor(live), contains(NetcruxAction.leaveSession));
      expect(
        paletteActionsFor(live),
        isNot(contains(NetcruxAction.joinSession)),
      );
    });
  });
}
