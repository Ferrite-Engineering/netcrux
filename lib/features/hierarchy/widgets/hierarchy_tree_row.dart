// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// A single row inside [HierarchyTreePanel]'s tree.
///
/// Leaf widget. Receives its data + callbacks via the constructor (per the
/// open-core widget rule "build for reuse"); no provider reads happen here so
/// the row is widget-testable in isolation. It is stateful to own the brief
/// background pulse it plays when [flashSignal] changes (the inbound
/// scope-highlight cue) — the flash target is still decided by the
/// parent, which passes a fresh [flashSignal] to exactly one row — and to
/// draw its focus ring.
///
/// **Keyboard and screen reader.** The row is one focusable, named node: a
/// button labelled with the scope and its cell count, carrying its selected
/// state and, when it has children, its expanded or collapsed state. Enter
/// or Space selects it. The panel makes the whole tree one Tab stop by
/// passing [isTabStop] true to a single row and moving focus between rows
/// with the arrow keys. The expand chevron is for the pointer only: it is
/// out of the Tab order and out of the accessibility tree, because the row
/// already announces the state it toggles and Right / Left change it.
class HierarchyTreeRow extends StatefulWidget {
  /// Creates a hierarchy tree row.
  const HierarchyTreeRow({
    required this.node,
    required this.depth,
    required this.isExpanded,
    required this.isSelected,
    required this.hasChildren,
    required this.cellCount,
    required this.instanceName,
    required this.moduleName,
    required this.onTap,
    this.onToggleExpand,
    this.flashSignal,
    this.focusNode,
    this.isTabStop = true,
    this.onFocusChange,
    super.key,
  });

  /// Fixed row height. The panel relies on it to scroll a row into view
  /// before that row has been built.
  static const double rowHeight = 28;

  /// Reserved for callers that need to round-trip through this widget
  /// (drag-and-drop, context menus). Exposed so the [HierarchyTreeRow]
  /// is a complete value carrier even though the row itself only uses
  /// it to compose its `key` semantics indirectly.
  final HierarchyNode node;

  /// Tree depth — 0 for the root, 1 for direct children, …. Controls
  /// the indent.
  final int depth;

  /// True when the row's children are showing.
  final bool isExpanded;

  /// True when this row is the currently selected scope.
  final bool isSelected;

  /// True when this scope contains user-defined-module children. Drives
  /// whether the expand chevron is interactive or just a placeholder.
  final bool hasChildren;

  /// Number of cells (primitives + child instances) inside this scope.
  /// Rendered as a compact "N cells" suffix on the row.
  final int cellCount;

  /// Display label — instance name (or top-module name at the root).
  final String instanceName;

  /// Module name — rendered in parentheses to the right of
  /// [instanceName] so the user can disambiguate two instances of the
  /// same module type.
  final String moduleName;

  /// Click, Enter or Space — selects this scope.
  final VoidCallback onTap;

  /// Click handler on the expand chevron — toggles expansion. `null`
  /// when [hasChildren] is false (the chevron is then a 16 dp empty
  /// placeholder to keep indent visually consistent across siblings).
  final VoidCallback? onToggleExpand;

  /// A monotonic flash token. When it changes to a non-null value the row
  /// plays a brief background pulse — the visible cue an inbound scope
  /// cross-probe fires. `null` (or an unchanged value) means "no
  /// flash": only the row the parent picked as the flash target receives a
  /// fresh token. Provider-free by design so the row stays testable in
  /// isolation.
  final int? flashSignal;

  /// The row's focus node, owned by the caller so it can move focus to the
  /// row. When null the row owns one.
  final FocusNode? focusNode;

  /// Whether Tab stops on this row. The tree gives the stop to one row.
  final bool isTabStop;

  /// Called when the row gains or loses keyboard focus.
  final ValueChanged<bool>? onFocusChange;

  @override
  State<HierarchyTreeRow> createState() => _HierarchyTreeRowState();
}

class _HierarchyTreeRowState extends State<HierarchyTreeRow>
    with SingleTickerProviderStateMixin {
  // Per-level indent. NetCrux is desktop-only (per netcrux/CLAUDE.md),
  // so a compact 16 dp indent fits the engineering-tool data-density
  // mandate; tablet rules in WaveCrux do not apply here.
  static const double _indentPerLevel = 16;

  // Chevron and icon sizes.
  static const double _chevronSize = 16;
  static const double _iconSize = 14;

  // The pulse fades from bright to nothing; the controller RESTS at 1.0
  // (fully faded) so a row that was never flashed shows no highlight.
  late final AnimationController _flash;

  FocusNode? _ownedFocusNode;
  bool _focused = false;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'HierarchyTreeRow'));

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
      value: 1,
    );
    if (widget.flashSignal != null) _flash.forward(from: 0);
  }

  @override
  void didUpdateWidget(HierarchyTreeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart the pulse whenever a fresh (changed, non-null) token arrives —
    // including a repeat flash of the same scope, whose token still differs.
    if (widget.flashSignal != null &&
        widget.flashSignal != oldWidget.flashSignal) {
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _activate() {
    _focusNode.requestFocus();
    widget.onTap();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10N.of(context);
    final color = widget.isSelected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final mutedColor = widget.isSelected
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.8)
        : theme.colorScheme.onSurfaceVariant;
    final label = _composeLabel(l10n);
    final cellCount = l10n.hierarchyCellCountLabel(widget.cellCount);

    final row = SizedBox(
      height: HierarchyTreeRow.rowHeight,
      child: Row(
        children: <Widget>[
          SizedBox(width: widget.depth * _indentPerLevel),
          _buildChevron(theme, l10n),
          const SizedBox(width: 2),
          Icon(
            widget.hasChildren
                ? Icons.account_tree_outlined
                : Icons.crop_square,
            size: _iconSize,
            color: mutedColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            cellCount,
            style: theme.textTheme.labelSmall?.copyWith(color: mutedColor),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );

    final baseColor = widget.isSelected
        ? theme.colorScheme.primary
        : Colors.transparent;
    return AnimatedBuilder(
      animation: _flash,
      // One node per row: a button named after the scope, with its selected
      // and expanded state, focusable through the Focus below. The visible
      // text and the chevron are excluded so nothing is announced twice.
      child: Semantics(
        container: true,
        button: true,
        selected: widget.isSelected,
        expanded: widget.hasChildren ? widget.isExpanded : null,
        label: '$label\n$cellCount',
        onTap: widget.onTap,
        child: Focus(
          focusNode: _focusNode,
          skipTraversal: !widget.isTabStop,
          onKeyEvent: _onKey,
          onFocusChange: (focused) {
            setState(() => _focused = focused);
            widget.onFocusChange?.call(focused);
          },
          child: InkWell(
            onTap: _activate,
            canRequestFocus: false,
            excludeFromSemantics: true,
            child: ExcludeSemantics(
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                // The keyboard focus ring. The row's own highlight is the
                // selection colour, so focus needs a mark of its own.
                decoration: BoxDecoration(
                  border: _focused
                      ? Border.all(color: theme.colorScheme.tertiary, width: 2)
                      : null,
                ),
                child: row,
              ),
            ),
          ),
        ),
      ),
      builder: (context, child) {
        // `_flash` runs 0→1; the pulse is brightest at the start and fades to
        // nothing (t: 1→0). Composited over the row's normal base colour so a
        // flash reads on both selected and unselected rows.
        final t = 1.0 - _flash.value;
        final flashColor = theme.colorScheme.tertiary.withValues(
          alpha: 0.60 * t,
        );
        return Material(
          color: t <= 0 ? baseColor : Color.alphaBlend(flashColor, baseColor),
          child: child,
        );
      },
    );
  }

  Widget _buildChevron(ThemeData theme, L10N l10n) {
    if (!widget.hasChildren) {
      return const SizedBox(width: _chevronSize, height: _chevronSize);
    }
    final tooltip = widget.isExpanded
        ? l10n.hierarchyCollapseTooltip
        : l10n.hierarchyExpandTooltip;
    return SizedBox(
      width: _chevronSize,
      height: _chevronSize,
      // Pointer only: Right / Left on the focused row expand and collapse.
      child: ExcludeFocus(
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: _chevronSize,
          constraints: const BoxConstraints(
            minWidth: _chevronSize,
            minHeight: _chevronSize,
          ),
          tooltip: tooltip,
          icon: Icon(
            widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
            color: widget.isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
          onPressed: widget.onToggleExpand,
        ),
      ),
    );
  }

  String _composeLabel(L10N l10n) {
    // Hide the module suffix for the root — there's no separate
    // instance name there, so `top (top)` would just look redundant.
    if (widget.depth == 0 || widget.instanceName == widget.moduleName) {
      return widget.instanceName;
    }
    return '${widget.instanceName} '
        '${l10n.hierarchyModuleLabel(widget.moduleName)}';
  }
}
