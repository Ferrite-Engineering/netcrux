// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/selection/element_path.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/services/trace_overlay_controller.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extensions_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_feature_tier_badge.dart';

/// Identifiers for the entries the schematic right-click context menu
/// can dispatch. Stable string ids so widget tests can find the menu
/// items via [PopupMenuItem.value].
enum SchematicContextMenuAction {
  /// Copies the canonical hierarchical path for the right-clicked
  /// element to the system clipboard.
  copyPath,

  /// Runs the fanin trace anchored on the right-clicked element.
  traceFanin,

  /// Runs the fanout trace anchored on the right-clicked element.
  traceFanout,

  /// Selects the parent scope of the right-clicked element in the
  /// hierarchy tree on the left pane.
  findInHierarchy,

  /// Promotes the right-clicked element to the primary selection so
  /// the inspector pane displays its details.
  openInInspector,
}

/// Coordinates the schematic-canvas right-click context menu.
///
/// Lives at the widget layer (not a service) because it needs the
/// `BuildContext` to show a [showMenu] overlay and the
/// `ScaffoldMessenger` to flash the "path copied" snackbar. Its
/// state-mutating helpers all dispatch into the same providers the
/// keyboard shortcuts and command palette use, so a future test can
/// assert behavior by reading the providers — no menu-item taps
/// required for unit coverage of the action wiring.
class SchematicContextMenuController {
  /// Creates a controller scoped to [ref], using [traceController]
  /// for the fanin / fanout actions. The trace controller is passed
  /// in (rather than constructed here) so widget tests can supply a
  /// recording stub.
  const SchematicContextMenuController({
    required this.ref,
    required this.traceController,
  });

  /// Reads / writes provider state.
  final WidgetRef ref;

  /// Trace overlay controller — reused for the menu's "Trace Fanin"
  /// / "Trace Fanout" entries so the action wiring matches the
  /// keyboard / command-palette dispatch.
  final TraceOverlayController traceController;

  /// Shows the schematic context menu at [globalPosition] for the
  /// element currently under the right-click. Returns the dispatched
  /// action (useful for tests) or `null` when the menu was dismissed
  /// without selection.
  Future<SchematicContextMenuAction?> showAt({
    required BuildContext context,
    required Offset globalPosition,
    required SelectedElement target,
  }) async {
    if (target.isNone) return null;
    final l10n = L10N.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    );
    // Gather the extension entries: the bookmark / annotation builder in
    // open core, plus whatever the Pro overlay's `proOverrides` registers
    // (cross-probe entries among them).
    final extensionBuilders = ref.read(schematicContextMenuExtensionsProvider);
    final extensions = <SchematicContextMenuExtensionEntry>[
      for (final builder in extensionBuilders) ...builder(ref, target),
    ];
    final items = <PopupMenuEntry<Object>>[
      PopupMenuItem<Object>(
        value: SchematicContextMenuAction.copyPath,
        child: Text(l10n.contextMenuCopyPath),
      ),
      PopupMenuItem<Object>(
        value: SchematicContextMenuAction.traceFanin,
        child: Text(l10n.contextMenuTraceFanin),
      ),
      PopupMenuItem<Object>(
        value: SchematicContextMenuAction.traceFanout,
        child: Text(l10n.contextMenuTraceFanout),
      ),
      PopupMenuItem<Object>(
        value: SchematicContextMenuAction.findInHierarchy,
        child: Text(l10n.contextMenuFindInHierarchy),
      ),
      PopupMenuItem<Object>(
        value: SchematicContextMenuAction.openInInspector,
        child: Text(l10n.contextMenuOpenInInspector),
      ),
      if (extensions.isNotEmpty) const PopupMenuDivider(),
      for (final ext in extensions)
        PopupMenuItem<Object>(
          value: ext,
          enabled: ext.enabled,
          child: _extensionChild(ext),
        ),
    ];
    final value = await showMenu<Object>(
      context: context,
      position: position,
      items: items,
    );
    if (value == null) return null;
    if (value is SchematicContextMenuAction) {
      if (!context.mounted) return value;
      await _dispatch(context: context, action: value, target: target);
      return value;
    }
    if (value is SchematicContextMenuExtensionEntry) {
      if (!context.mounted) return null;
      await value.onTap(context, ref);
      // Extension dispatches do not surface as a
      // SchematicContextMenuAction value (the enum is built-in only);
      // return null so callers can distinguish "built-in fired" from
      // "extension fired".
      return null;
    }
    return null;
  }

  /// Public dispatch entry point used by tests and by the menu
  /// callback above. Routes [action] to the right provider /
  /// controller call.
  Future<void> dispatch({
    required BuildContext context,
    required SchematicContextMenuAction action,
    required SelectedElement target,
  }) {
    return _dispatch(context: context, action: action, target: target);
  }

  Future<void> _dispatch({
    required BuildContext context,
    required SchematicContextMenuAction action,
    required SelectedElement target,
  }) async {
    switch (action) {
      case SchematicContextMenuAction.copyPath:
        await _copyPath(context: context, target: target);
      case SchematicContextMenuAction.traceFanin:
        ref.read(selectedElementProvider.notifier).select(target);
        traceController.showFanin();
      case SchematicContextMenuAction.traceFanout:
        ref.read(selectedElementProvider.notifier).select(target);
        traceController.showFanout();
      case SchematicContextMenuAction.findInHierarchy:
        _findInHierarchy();
      case SchematicContextMenuAction.openInInspector:
        ref.read(selectedElementProvider.notifier).select(target);
    }
  }

  Future<void> _copyPath({
    required BuildContext context,
    required SelectedElement target,
  }) async {
    final scope = ref.read(hierarchyTreeProvider).selected;
    if (scope == null) return;
    final model = ref.read(loadedNetlistProvider).value;
    final topModuleName = model?.topModule?.name;
    if (topModuleName == null) return;
    final path = buildElementPath(
      topModuleName: topModuleName,
      scope: scope,
      element: target,
    );
    if (path == null) return;
    await Clipboard.setData(ClipboardData(text: path));
    if (!context.mounted) return;
    final l10n = L10N.of(context);
    showCruxInfoSnack(context, l10n.contextMenuCopyPathSuccess(path));
  }

  Widget _extensionChild(SchematicContextMenuExtensionEntry ext) {
    final tier = ext.requiredTier;
    // The same chip the menu bar and the palette draw; it renders nothing
    // for the Open Core tier.
    final label = tier == null
        ? Text(ext.label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(child: Text(ext.label)),
              const SizedBox(width: 8),
              NetCruxFeatureTierBadge(requiredTier: tier),
            ],
          );
    final tooltip = ext.tooltip;
    if (tooltip == null) return label;
    return Tooltip(message: tooltip, child: label);
  }

  void _findInHierarchy() {
    // The hierarchy browser already shows the active scope's parent
    // chain via the breadcrumb. "Find in Hierarchy" promotes the
    // current scope (the element's parent) back to the selected
    // hierarchy row — useful when the user has been pushed deep into
    // a sub-scope and wants to confirm what's containing the element
    // they right-clicked. Re-selecting the scope is a no-op when the
    // tree is already focused there; it always scrolls the row into
    // view at the row level because the panel listens to selection
    // changes.
    final scope = ref.read(hierarchyTreeProvider).selected;
    if (scope == null) return;
    ref.read(hierarchyTreeProvider.notifier).selectByPath(scope.path);
  }
}
