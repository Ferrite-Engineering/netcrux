// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_row.dart';

/// A leaf row of the filtered hierarchy tree that is not a scope: a matching
/// cell listed under its scope, or the row that lists more of them.
///
/// Leaf widget, provider-free, with the same height, indent, focus ring and
/// one-node semantics as [HierarchyTreeRow] so the tree's roving focus and
/// fixed-extent scrolling treat every row alike. It has no chevron: there is
/// nothing below it to expand.
class HierarchyLeafRow extends StatefulWidget {
  /// Creates a leaf row.
  const HierarchyLeafRow({
    required this.depth,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onActivate,
    this.detail,
    this.isSelected = false,
    this.focusNode,
    this.isTabStop = true,
    this.onFocusChange,
    super.key,
  });

  /// Tree depth; controls the indent.
  final int depth;

  /// The glyph before the label: a cell row's chip icon or the "more" icon.
  final IconData icon;

  /// The visible text.
  final String label;

  /// Muted text after [label] (a cell's type), or null for none.
  final String? detail;

  /// What a screen reader announces for the row; the visible text is
  /// excluded so nothing is read twice.
  final String semanticLabel;

  /// Click, Enter or Space.
  final VoidCallback onActivate;

  /// True when the row is the current selection.
  final bool isSelected;

  /// The row's focus node, owned by the caller so it can move focus to the
  /// row. When null the row owns one.
  final FocusNode? focusNode;

  /// Whether Tab stops on this row. The tree gives the stop to one row.
  final bool isTabStop;

  /// Called when the row gains or loses keyboard focus.
  final ValueChanged<bool>? onFocusChange;

  @override
  State<HierarchyLeafRow> createState() => _HierarchyLeafRowState();
}

class _HierarchyLeafRowState extends State<HierarchyLeafRow> {
  // Matches HierarchyTreeRow's geometry: 16 dp per level, then the width a
  // chevron takes, so a leaf's icon lines up under its siblings' icons.
  static const double _indentPerLevel = 16;
  static const double _chevronSize = 16;
  static const double _iconSize = 14;

  FocusNode? _ownedFocusNode;
  bool _focused = false;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'HierarchyLeafRow'));

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _activate() {
    _focusNode.requestFocus();
    widget.onActivate();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      widget.onActivate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.isSelected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final mutedColor = widget.isSelected
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.8)
        : theme.colorScheme.onSurfaceVariant;
    final detail = widget.detail;
    final row = SizedBox(
      height: HierarchyTreeRow.rowHeight,
      child: Row(
        children: <Widget>[
          SizedBox(width: widget.depth * _indentPerLevel + _chevronSize + 2),
          Icon(widget.icon, size: _iconSize, color: mutedColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          if (detail != null) ...<Widget>[
            const SizedBox(width: 8),
            Text(
              detail,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(color: mutedColor),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
    );
    return Material(
      color: widget.isSelected ? theme.colorScheme.primary : Colors.transparent,
      child: Semantics(
        container: true,
        button: true,
        selected: widget.isSelected,
        label: widget.semanticLabel,
        onTap: widget.onActivate,
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
    );
  }
}
