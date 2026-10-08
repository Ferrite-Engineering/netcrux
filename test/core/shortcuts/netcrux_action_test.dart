// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings.dart';

void main() {
  group('NetcruxAction CruxAction conformance', () {
    test('every action has a netcrux-namespaced id', () {
      for (final action in NetcruxAction.values) {
        expect(
          action.id,
          startsWith('netcrux.'),
          reason: '$action must use the netcrux.* id namespace',
        );
        expect(action.id, equals('netcrux.${action.name}'));
      }
    });

    test('every action returns a valid ActionCategory', () {
      for (final action in NetcruxAction.values) {
        expect(
          ActionCategory.values,
          contains(action.category),
          reason: '$action.category must be a valid ActionCategory',
        );
      }
    });

    test('NetcruxActionIntent is a Flutter Intent', () {
      const intent = NetcruxActionIntent(NetcruxAction.openCommandPalette);
      expect(intent, isA<Intent>());
      expect(intent.action, NetcruxAction.openCommandPalette);
    });
  });

  group('defaultBindings', () {
    test('every NetcruxAction has a default key binding', () {
      // Of the four split-pane actions, closePane /
      // focusOtherPane / moveTabToOtherPane are command-palette-only
      // (their VSCode-equivalent chord bindings need chord support that
      // the current ShortcutManager does not have). Skip those here;
      // the conformance test below still confirms they have ids,
      // categories, and labels.
      const paletteOnly = <NetcruxAction>{
        NetcruxAction.closePane,
        NetcruxAction.focusOtherPane,
        NetcruxAction.moveTabToOtherPane,
        // Opening a pre-built netlist sits beside Open Source Files in the
        // File menu, toolbar and palette; the Cmd/Ctrl+O family is already
        // spent on projects, sources and sessions.
        NetcruxAction.openNetlistJson,
        // showCrossProbePanel is a command-palette + View menu action
        // with no chord binding, because the panel
        // is rare enough that a discoverable menu / palette entry is the
        // right surface.
        NetcruxAction.showCrossProbePanel,
        // The cone-of-influence actions are discoverable
        // through the command palette / menu; default key bindings can
        // be added later once usage patterns are clearer.
        NetcruxAction.showConeOfInfluenceFanin,
        NetcruxAction.showConeOfInfluenceFanout,
        NetcruxAction.clearConeOfInfluence,
        // X-trace — same rationale as cone-of-
        // influence: palette / menu discoverable, default chord
        // bindings deferred until usage patterns settle.
        NetcruxAction.showXTrace,
        NetcruxAction.showXTracePanel,
        NetcruxAction.clearXTrace,
        // Annotations — same palette / context-menu only convention.
        NetcruxAction.addAnnotation,
        NetcruxAction.showAnnotationsPanel,
        // RTL source pane — palette / menu / context-
        // menu discoverable; default chord bindings deferred until
        // the pane settles in usage.
        NetcruxAction.showSourcePane,
        NetcruxAction.openSourceForElement,
        NetcruxAction.closeSourcePane,
        // Netlist Diff View — palette / menu /
        // context-menu discoverable. Default chord bindings for
        // navigateNextDiff / navigatePrevDiff (F8 / Shift+F8) are
        // owned by the Pro panel's keyboard shortcuts widget, not
        // the open-core defaultBindings table.
        NetcruxAction.showDiffPane,
        NetcruxAction.loadComparisonNetlist,
        NetcruxAction.clearComparisonNetlist,
        NetcruxAction.navigateNextDiff,
        NetcruxAction.navigatePrevDiff,
        // Custom cell symbols — palette / menu /
        // context-menu discoverable; default chord bindings deferred
        // until usage patterns settle (Symbol Manager is a low-traffic
        // surface; the editor + remove actions are context-anchored).
        NetcruxAction.openSymbolManager,
        NetcruxAction.importSymbolFromSvg,
        NetcruxAction.editSymbolForCurrentInstance,
        NetcruxAction.removeSymbolForCurrentInstance,
        // FSM bubble diagram — palette / menu /
        // context-menu discoverable. Default chord bindings deferred
        // until usage patterns settle.
        NetcruxAction.showFsmBubbleDiagram,
        NetcruxAction.detectFsmForCurrentRegister,
        NetcruxAction.runFsmDetectionAcrossDesign,
        NetcruxAction.clearFsmSelection,
        // CDC visualization — palette / menu /
        // context-menu discoverable. Default chord bindings deferred
        // until usage patterns settle.
        NetcruxAction.showCdcAnalysisPane,
        NetcruxAction.runCdcAnalysis,
        NetcruxAction.showCdcCrossingForSelectedSignal,
        NetcruxAction.clearCdcAnalysisSelection,
        // Reset Domain visualization — palette / menu /
        // context-menu discoverable. Default chord bindings deferred
        // until usage patterns settle.
        NetcruxAction.showResetDomainAnalysisPane,
        NetcruxAction.runResetDomainAnalysis,
        NetcruxAction.showResetCrossingForSelectedSignal,
        NetcruxAction.clearResetAnalysisSelection,
        // Switching Activity Heatmap — palette / menu
        // discoverable. Default chord bindings deferred until usage
        // patterns settle.
        NetcruxAction.openWaveformFile,
        NetcruxAction.closeWaveformFile,
        NetcruxAction.showActivityHeatmap,
        NetcruxAction.runActivityAnalysis,
        NetcruxAction.clearActivityColoring,
        NetcruxAction.configureActivityScheme,
        // Beta-release infrastructure — Help-menu / palette /
        // About-box actions invoked a handful of times per release cycle.
        // A default chord would spend scarce keyboard real estate on
        // something nobody presses twice a day.
        NetcruxAction.checkForUpdates,
        NetcruxAction.submitIssue,
        // Documentation opens a URL in the browser — Help menu / palette.
        // F1 is About's binding across the suite.
        NetcruxAction.openDocumentation,
        // Workspace lifecycle. Destructive or
        // dialog-driven commands reached from the File menu and the palette;
        // WaveCrux and LintCrux leave the same set unbound.
        NetcruxAction.newWorkspace,
        NetcruxAction.openWorkspace,
        NetcruxAction.saveWorkspaceAs,
        NetcruxAction.resetWorkspace,
        NetcruxAction.toggleTheme,
        // Collaborative sessions: File menu and palette, unbound by default,
        // as in WaveCrux.
        NetcruxAction.shareSession,
        NetcruxAction.joinSession,
        NetcruxAction.leaveSession,
        // openAppDiagnostics and openTabDiagnostics are not in this set:
        // they carry WaveCrux's
        // Cmd/Ctrl+Shift+M and Cmd/Ctrl+Shift+I defaults respectively.
      };
      final bindings = defaultBindings();
      for (final action in NetcruxAction.values) {
        if (paletteOnly.contains(action)) continue;
        expect(
          bindings.containsKey(action),
          isTrue,
          reason: '$action is missing from defaultBindings()',
        );
      }
    });

    test('command palette binding is Ctrl/Cmd+Shift+P', () {
      final activator =
          defaultBindings()[NetcruxAction.openCommandPalette]!
              as SingleActivator;
      expect(activator.shift, isTrue);
      expect(activator.trigger.keyLabel.toUpperCase(), 'P');
    });

    test('design search binding is Ctrl/Cmd+F', () {
      // Search is the most-reached-for keyboard action on a loaded design;
      // an unbound Cmd+F reads as "the feature is missing" even though the
      // toolbar button still opens the dialog.
      final activator =
          defaultBindings()[NetcruxAction.openSearch]! as SingleActivator;
      expect(activator.trigger.keyLabel.toUpperCase(), 'F');
      expect(activator.shift, isFalse);
      expect(activator.alt, isFalse);
      expect(activator.meta || activator.control, isTrue);
    });

    test('Import Filelist is plain Ctrl/Cmd+I (suite import convention)', () {
      // Mirrors WaveCrux's importGtkwSession; Shift+I belongs to
      // openTabDiagnostics.
      final activator =
          defaultBindings()[NetcruxAction.importFilelist]! as SingleActivator;
      expect(activator.trigger, LogicalKeyboardKey.keyI);
      expect(activator.shift, isFalse);
      expect(activator.meta || activator.control, isTrue);
    });

    test('Tab Diagnostics is Ctrl/Cmd+Shift+I (WaveCrux parity)', () {
      final activator =
          defaultBindings()[NetcruxAction.openTabDiagnostics]!
              as SingleActivator;
      expect(activator.trigger, LogicalKeyboardKey.keyI);
      expect(activator.shift, isTrue);
      expect(activator.meta || activator.control, isTrue);
    });

    test('App Diagnostics is Ctrl/Cmd+Shift+M (WaveCrux parity)', () {
      final activator =
          defaultBindings()[NetcruxAction.openAppDiagnostics]!
              as SingleActivator;
      expect(activator.trigger, LogicalKeyboardKey.keyM);
      expect(activator.shift, isTrue);
      expect(activator.meta || activator.control, isTrue);
    });

    test('quit binding triggers on Q', () {
      final activator =
          defaultBindings()[NetcruxAction.quit]! as SingleActivator;
      expect(activator.trigger.keyLabel.toUpperCase(), 'Q');
    });
  });

  group('NetcruxActionRequiredTier', () {
    test('Pro cone-of-influence trace actions require LicenseTier.pro', () {
      expect(
        NetcruxAction.showConeOfInfluenceFanin.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.showConeOfInfluenceFanout.requiredTier,
        LicenseTier.pro,
      );
    });

    test('Pro X-trace action requires LicenseTier.pro', () {
      expect(NetcruxAction.showXTrace.requiredTier, LicenseTier.pro);
    });

    test('Pro RTL source pane actions require LicenseTier.pro', () {
      expect(NetcruxAction.showSourcePane.requiredTier, LicenseTier.pro);
      expect(
        NetcruxAction.openSourceForElement.requiredTier,
        LicenseTier.pro,
      );
    });

    test('Pro Netlist Diff View actions require LicenseTier.pro', () {
      expect(NetcruxAction.showDiffPane.requiredTier, LicenseTier.pro);
      expect(
        NetcruxAction.loadComparisonNetlist.requiredTier,
        LicenseTier.pro,
      );
      expect(NetcruxAction.navigateNextDiff.requiredTier, LicenseTier.pro);
      expect(NetcruxAction.navigatePrevDiff.requiredTier, LicenseTier.pro);
    });

    test('every clear / dismiss action is Open Core', () {
      // The dispatcher never wraps a clear in the tier gate, and
      // open-core resolves each clear opener to a no-op, so a Pro tier on
      // one of these would badge an action a licence cannot unlock.
      for (final action in <NetcruxAction>[
        NetcruxAction.clearOverlay,
        NetcruxAction.clearConeOfInfluence,
        NetcruxAction.clearXTrace,
        NetcruxAction.clearComparisonNetlist,
        NetcruxAction.clearFsmSelection,
        NetcruxAction.clearCdcAnalysisSelection,
        NetcruxAction.clearResetAnalysisSelection,
        NetcruxAction.clearActivityColoring,
      ]) {
        expect(action.requiredTier, LicenseTier.openCore, reason: '$action');
      }
    });

    test('closeSourcePane is Open Core (dismissing is never gated)', () {
      expect(NetcruxAction.closeSourcePane.requiredTier, LicenseTier.openCore);
    });

    test('annotation actions are Open Core and gate nothing', () {
      // Annotations are free: the add action and the panel
      // toggle carry no tier and no feature id a denial could report.
      for (final action in <NetcruxAction>[
        NetcruxAction.addAnnotation,
        NetcruxAction.showAnnotationsPanel,
      ]) {
        expect(action.requiredTier, LicenseTier.openCore, reason: '$action');
        expect(action.gatedFeature, isNull, reason: '$action');
      }
    });

    test('clearConeOfInfluence is Open Core (clearing is always allowed)', () {
      expect(
        NetcruxAction.clearConeOfInfluence.requiredTier,
        LicenseTier.openCore,
      );
    });

    test(
      'clearXTrace + showXTracePanel are Open Core (visible regardless)',
      () {
        expect(NetcruxAction.clearXTrace.requiredTier, LicenseTier.openCore);
        expect(
          NetcruxAction.showXTracePanel.requiredTier,
          LicenseTier.openCore,
        );
      },
    );

    test('every other action stays Open Core by default', () {
      const proActions = <NetcruxAction>{
        // Hosting a collaborative session is the one Enterprise action.
        NetcruxAction.shareSession,
        NetcruxAction.showConeOfInfluenceFanin,
        NetcruxAction.showConeOfInfluenceFanout,
        NetcruxAction.showXTrace,
        NetcruxAction.showSourcePane,
        NetcruxAction.openSourceForElement,
        NetcruxAction.showDiffPane,
        NetcruxAction.loadComparisonNetlist,
        NetcruxAction.clearComparisonNetlist,
        NetcruxAction.navigateNextDiff,
        NetcruxAction.navigatePrevDiff,
        NetcruxAction.openSymbolManager,
        NetcruxAction.importSymbolFromSvg,
        NetcruxAction.editSymbolForCurrentInstance,
        NetcruxAction.removeSymbolForCurrentInstance,
        NetcruxAction.showFsmBubbleDiagram,
        NetcruxAction.detectFsmForCurrentRegister,
        NetcruxAction.runFsmDetectionAcrossDesign,
        NetcruxAction.showCdcAnalysisPane,
        NetcruxAction.runCdcAnalysis,
        NetcruxAction.showCdcCrossingForSelectedSignal,
        NetcruxAction.showResetDomainAnalysisPane,
        NetcruxAction.runResetDomainAnalysis,
        NetcruxAction.showResetCrossingForSelectedSignal,
        NetcruxAction.openWaveformFile,
        NetcruxAction.closeWaveformFile,
        NetcruxAction.showActivityHeatmap,
        NetcruxAction.runActivityAnalysis,
        NetcruxAction.configureActivityScheme,
      };
      for (final action in NetcruxAction.values) {
        if (proActions.contains(action)) continue;
        expect(
          action.requiredTier,
          LicenseTier.openCore,
          reason: '$action is not a Pro action and should map to openCore',
        );
      }
    });

    test('FSM bubble diagram actions are Pro tier', () {
      expect(
        NetcruxAction.showFsmBubbleDiagram.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.detectFsmForCurrentRegister.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.runFsmDetectionAcrossDesign.requiredTier,
        LicenseTier.pro,
      );
      // clearFsmSelection stays Open Core (dismissing is never gated).
      expect(
        NetcruxAction.clearFsmSelection.requiredTier,
        LicenseTier.openCore,
      );
    });

    test('CDC analysis actions are Pro tier', () {
      expect(
        NetcruxAction.showCdcAnalysisPane.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.runCdcAnalysis.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.showCdcCrossingForSelectedSignal.requiredTier,
        LicenseTier.pro,
      );
      // clearCdcAnalysisSelection stays Open Core.
      expect(
        NetcruxAction.clearCdcAnalysisSelection.requiredTier,
        LicenseTier.openCore,
      );
    });

    test('Reset Domain analysis actions are Pro tier', () {
      expect(
        NetcruxAction.showResetDomainAnalysisPane.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.runResetDomainAnalysis.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.showResetCrossingForSelectedSignal.requiredTier,
        LicenseTier.pro,
      );
      // clearResetAnalysisSelection stays Open Core.
      expect(
        NetcruxAction.clearResetAnalysisSelection.requiredTier,
        LicenseTier.openCore,
      );
    });

    test('Switching Activity Heatmap actions are Pro tier', () {
      expect(
        NetcruxAction.openWaveformFile.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.closeWaveformFile.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.showActivityHeatmap.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.runActivityAnalysis.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.configureActivityScheme.requiredTier,
        LicenseTier.pro,
      );
      // clearActivityColoring stays Open Core (clearing is never gated).
      expect(
        NetcruxAction.clearActivityColoring.requiredTier,
        LicenseTier.openCore,
      );
    });

    test('Custom cell symbol actions are Pro tier', () {
      expect(
        NetcruxAction.openSymbolManager.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.importSymbolFromSvg.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.editSymbolForCurrentInstance.requiredTier,
        LicenseTier.pro,
      );
      expect(
        NetcruxAction.removeSymbolForCurrentInstance.requiredTier,
        LicenseTier.pro,
      );
    });
  });
}
