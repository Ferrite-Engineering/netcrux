// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/license/netcrux_edition_line_strings.dart';
import 'package:netcrux/core/shortcuts/action_category.dart';
import 'package:netcrux/core/shortcuts/action_tier_label.dart';
import 'package:netcrux/core/shortcuts/menu_layout.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptor.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptors.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:netcrux/features/workspace/providers/netcrux_action_context_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_icon_image.dart';

/// NetCrux's binding of the shared [CruxDesktopMenuBar] to its own action
/// catalog.
///
/// Everything structural — the two renderers (native macOS [PlatformMenuBar]
/// vs. the in-window VS Code-style menu bar on Windows/Linux), separator
/// grouping, the platform-idiomatic placement of About / Check for Updates /
/// Settings / Quit, the standard macOS application-menu tail and Window menu,
/// and the guard that keeps typing-hostile accelerators out of native key
/// equivalents — lives in `crux_menu_bar`. This widget supplies only what is
/// NetCrux's own: [kMenuLayout] for order and grouping, the descriptor table
/// for membership and enablement, and the localized labels.
///
/// The bare `[` / `]` / Escape accelerators NetCrux binds are no longer
/// published to the macOS menu: an `NSMenuItem` key equivalent is matched
/// ahead of the focused view, so a bare `[` there stopped the user typing a
/// bracket into the design-search field. They still fire through the
/// `Shortcuts` layer, and Windows/Linux still show them as labels.
class DesktopMenuBar extends ConsumerWidget {
  /// Creates the NetCrux desktop menu bar.
  const DesktopMenuBar({
    required this.onAction,
    required this.child,
    super.key,
  });

  /// Called when the user selects a menu item.
  final void Function(NetcruxAction) onAction;

  /// The widget tree below the menu bar.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final ctx = ref.watch(netcruxActionContextProvider);
    final bindings = ref.watch(shortcutBindingsProvider);
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;

    return CruxDesktopMenuBar<NetcruxAction>(
      layout: kMenuLayout,
      appActions: kAppMenuActions,
      categoryLabel: (category) => category.label(l10n),
      categoryAcceleratorLabel: (category) => category.acceleratorLabel(l10n),
      windowMenuLabel: l10n.menuWindow,
      labelOf: (action) =>
          _label(action, l10n, isMacOS: isMacOS) +
          tierLabelSuffix(action.requiredTier, l10n),
      shortcutOf: (action) => bindings[action],
      isVisible: (action) =>
          isActionVisibleIn(action, NetcruxActionSurface.menu, ctx),
      isEnabled: (action) => isActionEnabled(action, ctx),
      onAction: onAction,
      // States the edition in force, disabled, above `About NetCrux`.
      // Null at Open Core, so this is safe to pass unconditionally: the
      // Pro overlay supplies the licence status that gives it a value.
      editionLine: cruxLicenseEditionLine(
        ref.watch(licenseStatusProvider),
        NetCruxEditionLineStrings(l10n),
      ),
      logo: const NetcruxIconImage(size: 18),
      child: child,
    );
  }

  /// The action's localized label, with the one platform-dependent override.
  ///
  /// Quit reads "Quit NetCrux" in the macOS application menu and "Exit" at the
  /// bottom of the Windows/Linux File menu — the native wording on each, and
  /// what VS Code does.
  static String _label(
    NetcruxAction action,
    L10N l10n, {
    required bool isMacOS,
  }) => action == NetcruxAction.quit && !isMacOS
      ? l10n.actionExit
      : action.label(l10n);
}
