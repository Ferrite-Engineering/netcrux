// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart' as kb;
import 'package:flutter/widgets.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings.dart';

/// Activator combinations more than one [NetcruxAction] is *intentionally*
/// allowed to share, so conflict resolution doesn't flag them. NetCrux has no
/// by-design keyboard shadows; the set exists so the same wrapper shape as
/// WaveCrux is available if one is ever introduced.
const Set<Set<NetcruxAction>> kIntentionalShadows = {};

/// NetCrux-flavored conflict *resolution*: delegates to the cross-suite
/// `resolveShortcutConflicts`, injecting [defaultBindings], [NetcruxAction]
/// declaration order (for the deterministic tiebreak), and
/// [kIntentionalShadows].
///
/// Returns both the deterministic runtime activator map
/// ([kb.ShortcutConflictResolution.effectiveBindings] — fed to
/// `ShortcutManagerWidget` so a user-remapped binding wins its chord instead of
/// the enum-declaration-order accident) and the editor's owner/shadowed view.
kb.ShortcutConflictResolution<NetcruxAction> resolveShortcutConflicts(
  Map<NetcruxAction, ShortcutActivator> bindings,
) => kb.resolveShortcutConflicts(
  bindings,
  defaultBindings(),
  order: NetcruxAction.values,
  intentionalShadows: kIntentionalShadows,
);
