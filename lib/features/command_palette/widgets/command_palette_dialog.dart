// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_keybindings/crux_keybindings.dart'
    show formatShortcutLabel;
import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptors.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:netcrux/features/workspace/providers/netcrux_action_context_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_feature_tier_badge.dart';

/// Netcrux-specific wrapper around the cross-suite
/// [CommandPalette]<[NetcruxAction]> widget.
///
/// Responsibilities:
/// - List the actions the descriptor table prescribes for the palette
///   surface (`paletteActionsFor` — visible AND enabled; the palette has
///   no greyed state, so disabled actions are omitted).
/// - Resolve action labels through netcrux's [L10N] class.
/// - Pass the active key bindings so each row can render its shortcut.
/// - Dispatch the selected action by invoking [onAction], leaving the
///   actual handler logic to the caller (typically the project viewer
///   route).
class CommandPaletteDialog extends ConsumerWidget {
  /// Creates a netcrux command palette wrapper.
  const CommandPaletteDialog({required this.onAction, super.key});

  /// Called when the user picks an action. The dialog has already closed
  /// itself by the time this fires.
  final ValueChanged<NetcruxAction> onAction;

  /// Shows the palette as a modal dialog over [context].
  ///
  /// Re-entrancy guarded ([ModalGuard]): Cmd/Ctrl+Shift+P auto-repeat or a
  /// double-press must not stack multiple palettes. Guarded inside the
  /// opener so every caller is covered.
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<NetcruxAction> onAction,
  }) {
    final container = ProviderScope.containerOf(context, listen: false);
    return ModalGuard.run(
      'commandPalette',
      () => CommandPalette.show<NetcruxAction>(
        context,
        actions: paletteActionsFor(
          container.read(netcruxActionContextProvider),
        ),
        labelFor: (a) => a.label(L10N.of(context)),
        onAction: onAction,
        hintText: L10N.of(context).commandPaletteSearchHint,
        noResultsLabel: L10N.of(context).commandPaletteNoResults,
        bindings: _readBindings(context),
        activatorLabel: formatShortcutLabel,
        trailingBuilder: _tierBadge,
      ),
    );
  }

  /// Renders a [NetCruxFeatureTierBadge] to the right of each Pro/Enterprise
  /// action's label, per the CLAUDE.md rule that every action-discovery
  /// surface communicates tier from the action's
  /// [NetcruxActionRequiredTier.requiredTier]. Open-core actions get no
  /// trailing widget (return `null`) so free rows stay unadorned.
  static Widget? _tierBadge(NetcruxAction action) {
    final tier = action.requiredTier;
    if (tier == LicenseTier.openCore) return null;
    return NetCruxFeatureTierBadge(requiredTier: tier);
  }

  /// Reads the active bindings via a one-shot `ProviderScope.containerOf`
  /// lookup so [show] can be invoked from anywhere without a `WidgetRef`
  /// in hand.
  static Map<NetcruxAction, ShortcutActivator?> _readBindings(
    BuildContext context,
  ) {
    final container = ProviderScope.containerOf(context, listen: false);
    return container.read(shortcutBindingsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final bindings = ref.watch(shortcutBindingsProvider);
    return CommandPalette<NetcruxAction>(
      actions: paletteActionsFor(ref.watch(netcruxActionContextProvider)),
      labelFor: (a) => a.label(l10n),
      onAction: onAction,
      hintText: l10n.commandPaletteSearchHint,
      noResultsLabel: l10n.commandPaletteNoResults,
      bindings: bindings,
      activatorLabel: formatShortcutLabel,
      trailingBuilder: _tierBadge,
    );
  }
}
