// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// NetCrux-localized [`ViewerTabBarStrings`] adapter.
///
/// `crux_workspace` ships a [`ViewerTabBarStringsEn`] default with bare
/// English strings — products that have ARB-generated localizations
/// subclass [`ViewerTabBarStrings`] and route each getter through their
/// own [`L10N`]. NetCrux supplies the ARB entries in `app_en.arb` /
/// `app_zh_CN.arb` / `app_zh.arb` / `app_ja.arb` / `app_ko.arb`; this adapter
/// forwards each
/// interface field to the matching getter.
class NetcruxViewerTabBarStrings extends ViewerTabBarStrings {
  /// Wraps the supplied [`L10N`] instance so each interface getter
  /// returns the live-localized value for the active locale.
  const NetcruxViewerTabBarStrings(this._l10n);

  final L10N _l10n;

  @override
  String get revealTabMenuItem {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return _l10n.tabContextMenuRevealInExplorer;
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return _l10n.tabContextMenuRevealInFiles;
    }
    return _l10n.tabContextMenuRevealInFinder;
  }

  @override
  String get closeTabTooltip => _l10n.viewerTabBarCloseTabTooltip;

  /// Names the tab, so a screen reader moving through several open tabs
  /// hears which one the close button closes ("Close top.v"), not the same
  /// "Close tab" on every chip.
  @override
  String closeTabTooltipFor(String name) =>
      _l10n.viewerTabBarCloseTabTooltipFor(name);

  @override
  String get newTabTooltip => _l10n.viewerTabBarNewTabTooltip;

  @override
  String get newTabDefaultDisplayName =>
      _l10n.viewerTabBarNewTabDefaultDisplayName;

  @override
  String get unnamedTabFallback => _l10n.viewerTabBarUnnamedTabFallback;

  @override
  String get closeTabMenuItem => _l10n.viewerTabBarCloseTabMenuItem;

  @override
  String get closeOtherTabsMenuItem => _l10n.viewerTabBarCloseOtherTabsMenuItem;

  @override
  String get closeTabsToTheRightMenuItem =>
      _l10n.viewerTabBarCloseTabsToTheRightMenuItem;

  @override
  String get moveToNewWindowMenuItem =>
      _l10n.viewerTabBarMoveToNewWindowMenuItem;

  @override
  String get multiWindowUnavailableTooltip =>
      _l10n.viewerTabBarMultiWindowUnavailableTooltip;

  @override
  String get activePaneAccessibilityLabel =>
      _l10n.viewerTabBarActivePaneAccessibilityLabel;

  @override
  String get dragToPaneAccessibilityHint =>
      _l10n.viewerTabBarDragToPaneAccessibilityHint;

  @override
  String get reorderHandleTooltip => _l10n.viewerTabBarReorderHandleTooltip;

  // These two carry an English default on the shared interface (they were added
  // after four products already subclassed it), so an override is what stops
  // NetCrux silently announcing "Scroll tabs left" in Japanese.
  @override
  String get scrollTabsLeftTooltip => _l10n.viewerTabBarScrollTabsLeftTooltip;

  @override
  String get scrollTabsRightTooltip => _l10n.viewerTabBarScrollTabsRightTooltip;
}
