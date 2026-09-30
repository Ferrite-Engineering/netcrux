// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';

/// The three action-discovery surfaces a [NetcruxAction] can appear in.
///
/// The toolbar is the one-click tier; the native menu bar is the browsable
/// categorized tier; the command palette is the search tier. NetCrux has no
/// mobile overflow menu (desktop + read-only web only), so the surface set
/// is one smaller than WaveCrux's.
enum NetcruxActionSurface {
  /// The tier-1 action toolbar above the tab strip.
  toolbar,

  /// The native desktop menu bar (`PlatformMenuBar`).
  menu,

  /// The command palette (Ctrl/Cmd+Shift+P).
  palette,
}

/// Declarative description of where a single [NetcruxAction] appears and
/// when it is visible / enabled. The table of these in
/// `netcrux_action_descriptors.dart` is the **single source of truth**
/// consumed by every action-discovery surface, replacing the per-surface
/// hidden-action sets that used to drift apart.
///
/// ## Presentation policy (how surfaces interpret a descriptor)
///
/// An action **appears** in surface `s` iff `surfaces.contains(s) &&
/// isVisible(ctx)`. Once it appears:
///
/// - **menu**: the item is rendered, and is *enabled* iff `isEnabled(ctx)`
///   (a disabled item is greyed out, not hidden).
/// - **palette**: the item is *listed* iff it also satisfies
///   `isEnabled(ctx)` — the palette has no greyed state, so a disabled
///   action is simply omitted.
/// - **toolbar**: the button is rendered, and is enabled iff
///   `isEnabled(ctx)`.
/// - **keyboard**: the shortcut dispatch path checks `isEnabled(ctx)`
///   before invoking, so a disabled action's chord is inert rather than a
///   silent handler-side no-op.
///
/// So [isVisible] models *structural* gating that hides an action
/// everywhere, while [isEnabled] models *transient* gating (a design-
/// required action with no design loaded; a selection-seeded action with
/// nothing selected).
///
/// The minimum license tier is deliberately NOT a descriptor field: it
/// stays declared once on `NetcruxActionRequiredTier.requiredTier` (the
/// extension the surfaces, the tier badge, and the dispatcher's gate
/// already consume), so tier cannot be declared in two places that drift.
@immutable
class NetcruxActionDescriptor {
  /// Creates a descriptor. Defaults: no surfaces (keyboard / context-menu
  /// reachable only), always visible, always enabled.
  const NetcruxActionDescriptor({
    this.surfaces = const {},
    this.isVisible = _alwaysTrue,
    this.isEnabled = _alwaysTrue,
  });

  /// The surfaces this action can appear in. An empty set means the
  /// action is reachable only via keyboard shortcut or a context menu.
  final Set<NetcruxActionSurface> surfaces;

  /// Structural visibility predicate. When it returns false the action is
  /// omitted from *all* surfaces. Defaults to always-visible.
  final bool Function(NetcruxActionContext) isVisible;

  /// Transient enablement predicate. Defaults to always-enabled. See the
  /// class doc for how each surface presents a disabled action.
  final bool Function(NetcruxActionContext) isEnabled;

  static bool _alwaysTrue(NetcruxActionContext _) => true;
}
