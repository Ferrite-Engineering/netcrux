// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/hierarchy/providers/scope_flash_notifier.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_row.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/hierarchy/hierarchy_walk.dart';

/// Left-pane hierarchy tree browser.
///
/// Renders the elaborated [NetlistModel] as an indented expand/collapse
/// tree rooted at the top module. Filtering is a case-insensitive
/// substring match against either the instance name *or* the module
/// name of each scope; a parent is rendered when any descendant
/// matches so the user can still see where the hit lives.
///
/// Interactions: click-to-select, expand/collapse via chevron, inline
/// filter field.
class HierarchyTreePanel extends ConsumerStatefulWidget {
  /// Creates a hierarchy tree panel.
  const HierarchyTreePanel({super.key});

  @override
  ConsumerState<HierarchyTreePanel> createState() => _HierarchyTreePanelState();
}

class _HierarchyTreePanelState extends ConsumerState<HierarchyTreePanel> {
  late final TextEditingController _filterController;

  @override
  void initState() {
    super.initState();
    _filterController = TextEditingController(
      text: ref.read(hierarchyTreeProvider).filterText,
    );
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(hierarchyTreeProvider);

    // Sync the controller back to the notifier state when something
    // else (CLI launch, test override) loaded a different filter.
    if (_filterController.text != state.filterText) {
      _filterController.value = TextEditingValue(
        text: state.filterText,
        selection: TextSelection.collapsed(offset: state.filterText.length),
      );
    }

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _HierarchyFilterField(controller: _filterController),
          const Divider(height: 1),
          Expanded(
            child: _HierarchyTreeBody(state: state, l10n: l10n),
          ),
        ],
      ),
    );
  }
}

class _HierarchyFilterField extends ConsumerWidget {
  const _HierarchyFilterField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      // Its own semantics container: otherwise the field becomes the node
      // that also carries the dock's region label and header text, so it is
      // announced as "Browser dock Hierarchy Filter scopes…", and the dock's
      // Hide Panel button and every tree row are read as its children.
      child: Semantics(
        container: true,
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
            hintText: l10n.hierarchyFilterHint,
            border: const OutlineInputBorder(),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.hierarchyClearFilterTooltip,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      controller.clear();
                      ref
                          .read(hierarchyTreeProvider.notifier)
                          .setFilterText('');
                    },
                  ),
          ),
          onChanged: (value) =>
              ref.read(hierarchyTreeProvider.notifier).setFilterText(value),
        ),
      ),
    );
  }
}

class _HierarchyTreeBody extends ConsumerWidget {
  const _HierarchyTreeBody({required this.state, required this.l10n});

  final HierarchyTreeState state;
  final L10N l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = state.model;
    final root = state.root;
    if (model == null) {
      // Distinguish "no design loaded" (truly empty tab) from
      // "elaboration failed" (project pointed at sources but yosys
      // missing, file not found, parse error, …). Without this branch
      // the user sees the "Open a design" placeholder even after
      // selecting a project whose elaboration just threw.
      final loadedAsync = ref.watch(loadedNetlistProvider);
      if (loadedAsync.hasError) {
        final error = loadedAsync.error;
        final message = error is LoadedNetlistException
            ? error.message
            : '$error';
        return _EmptyMessage(
          text: l10n.hierarchyEmptyElaborationFailed(message),
          isError: true,
        );
      }
      return _EmptyMessage(text: l10n.hierarchyEmptyNoDesign);
    }
    if (root == null) {
      return _EmptyMessage(text: l10n.hierarchyEmptyNoTop);
    }
    final rows = buildVisibleRows(
      model: model,
      state: state,
    );
    if (rows.isEmpty) {
      // The model has a root, but the filter wiped everything out.
      return _EmptyMessage(text: l10n.hierarchyFilterNoMatches);
    }
    return _HierarchyTreeList(rows: rows, state: state);
  }
}

/// The tree rows as one keyboard stop.
///
/// Tab reaches the tree once, on the row holding the stop: the selected
/// scope when the selection changed since the tree last had focus,
/// otherwise the row focused last. Inside it:
///
/// | Key          | Effect                                                   |
/// |--------------|----------------------------------------------------------|
/// | Up / Down    | Previous / next visible row                              |
/// | Home / End   | First / last row                                         |
/// | Right        | Expand; on an expanded row, move to its first child      |
/// | Left         | Collapse; on a collapsed or leaf row, move to its parent |
/// | Enter, Space | Select the scope (handled by the row)                    |
///
/// Focus moves between real per-row focus nodes (roving focus), so a screen
/// reader announces each row as it arrives. A row that has not been built
/// yet is scrolled into view first and focused once it is laid out.
class _HierarchyTreeList extends ConsumerStatefulWidget {
  const _HierarchyTreeList({required this.rows, required this.state});

  final List<HierarchyVisibleRow> rows;
  final HierarchyTreeState state;

  @override
  ConsumerState<_HierarchyTreeList> createState() => _HierarchyTreeListState();
}

class _HierarchyTreeListState extends ConsumerState<_HierarchyTreeList> {
  final ScrollController _scroll = ScrollController();
  final Map<String, FocusNode> _nodes = <String, FocusNode>{};
  String? _stopKey;
  String? _lastSelectedKey;
  bool _pruneScheduled = false;

  static String _keyOf(HierarchyVisibleRow row) => row.node.path.join('/');

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(String key) =>
      _nodes[key] ??= FocusNode(debugLabel: 'Hierarchy row $key');

  bool get _treeHasFocus => _nodes.values.any((node) => node.hasFocus);

  /// Keeps the Tab stop on a row that exists, following the selection when
  /// it changes while the tree is not being walked.
  void _settleStop(List<String> keys) {
    final selected = widget.state.selected;
    final selectedKey = selected?.path.join('/');
    if (selectedKey != _lastSelectedKey) {
      _lastSelectedKey = selectedKey;
      if (!_treeHasFocus && keys.contains(selectedKey)) _stopKey = selectedKey;
    }
    final stop = _stopKey;
    if (stop != null && keys.contains(stop)) return;
    // The stop's row went away (a collapse, a filter): the nearest ancestor
    // still showing takes it, else the first row.
    var candidate = stop;
    while (candidate != null && candidate.isNotEmpty) {
      final cut = candidate.lastIndexOf('/');
      candidate = cut == -1 ? '' : candidate.substring(0, cut);
      if (keys.contains(candidate)) {
        _stopKey = candidate;
        return;
      }
    }
    _stopKey = keys.contains(selectedKey) ? selectedKey : keys.first;
  }

  /// Disposes the focus nodes of rows that are no longer in the tree, after
  /// the frame that removed them has unmounted their widgets.
  void _schedulePrune(List<String> keys) {
    if (_pruneScheduled) return;
    _pruneScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pruneScheduled = false;
      if (!mounted) return;
      final live = widget.rows.map(_keyOf).toSet();
      final stale = _nodes.keys.where((key) => !live.contains(key)).toList();
      for (final key in stale) {
        _nodes.remove(key)?.dispose();
      }
    });
  }

  void _onRowFocused(String key) {
    // Deferred: this runs from a focus-node listener, and the rebuild it
    // triggers changes other rows' focus-node properties.
    scheduleMicrotask(() {
      if (!mounted || _stopKey == key) return;
      setState(() => _stopKey = key);
    });
  }

  void _focusRow(int index) {
    final rows = widget.rows;
    if (index < 0 || index >= rows.length) return;
    final key = _keyOf(rows[index]);
    if (_stopKey != key) setState(() => _stopKey = key);
    _scrollIntoView(index);
    final node = _nodes[key];
    if (node != null && node.context != null) {
      node.requestFocus();
      return;
    }
    // Not built yet: it is after the scroll above lays it out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes[key]?.requestFocus();
    });
  }

  void _scrollIntoView(int index) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final top = index * HierarchyTreeRow.rowHeight;
    final bottom = top + HierarchyTreeRow.rowHeight;
    double? target;
    if (top < position.pixels) {
      target = top;
    } else if (bottom > position.pixels + position.viewportDimension) {
      target = bottom - position.viewportDimension;
    }
    if (target == null) return;
    _scroll.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  /// Whether the row at [index] is showing its children.
  bool _showsChildren(int index) {
    final rows = widget.rows;
    return index + 1 < rows.length && rows[index + 1].depth > rows[index].depth;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final rows = widget.rows;
    final current = rows.indexWhere(
      (row) => _nodes[_keyOf(row)]?.hasPrimaryFocus ?? false,
    );
    if (current == -1) return KeyEventResult.ignored;
    final row = rows[current];
    final notifier = ref.read(hierarchyTreeProvider.notifier);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _focusRow(current + 1);
      case LogicalKeyboardKey.arrowUp:
        _focusRow(current - 1);
      case LogicalKeyboardKey.home:
        _focusRow(0);
      case LogicalKeyboardKey.end:
        _focusRow(rows.length - 1);
      case LogicalKeyboardKey.arrowRight:
        if (_showsChildren(current)) {
          _focusRow(current + 1);
        } else if (row.hasChildren) {
          notifier.expandScope(row.node);
        }
      case LogicalKeyboardKey.arrowLeft:
        if (_showsChildren(current) && !row.node.isRoot) {
          notifier.collapseScope(row.node);
        } else {
          final parent = rows.lastIndexWhere(
            (candidate) => candidate.depth == row.depth - 1,
            current,
          );
          if (parent != -1) _focusRow(parent);
        }
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final rows = widget.rows;
    final keys = rows.map(_keyOf).toList();
    _settleStop(keys);
    _schedulePrune(keys);
    // The pending scope-flash request (an inbound scope cross-probe cue). Only
    // the row whose node path matches receives the flash token, so exactly one
    // row pulses.
    final flash = ref.watch(scopeFlashProvider);
    final notifier = ref.read(hierarchyTreeProvider.notifier);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _onKey,
      child: Scrollbar(
        controller: _scroll,
        child: ListView.builder(
          controller: _scroll,
          itemExtent: HierarchyTreeRow.rowHeight,
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final key = keys[index];
            final flashSignal = (flash != null && key == flash.pathKey)
                ? flash.nonce
                : null;
            return HierarchyTreeRow(
              key: ValueKey<String>(key),
              node: row.node,
              depth: row.depth,
              isExpanded: _showsChildren(index),
              isSelected: state.isSelected(row.node),
              hasChildren: row.hasChildren,
              cellCount: row.cellCount,
              instanceName: row.instanceName,
              moduleName: row.moduleName,
              flashSignal: flashSignal,
              focusNode: _nodeFor(key),
              isTabStop: key == _stopKey,
              onFocusChange: (focused) {
                if (focused) _onRowFocused(key);
              },
              onTap: () => notifier.selectScope(row.node),
              onToggleExpand: row.hasChildren
                  ? () => notifier.toggleScope(row.node)
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isError)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Icon(
                  Icons.error_outline,
                  color: color,
                ),
              ),
            SelectableText(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flattened row produced by [buildVisibleRows] for one visible scope.
class HierarchyVisibleRow {
  /// Creates a visible row.
  const HierarchyVisibleRow({
    required this.node,
    required this.depth,
    required this.instanceName,
    required this.moduleName,
    required this.hasChildren,
    required this.cellCount,
  });

  /// The [HierarchyNode] this row represents.
  final HierarchyNode node;

  /// Indent depth: 0 = root, 1 = first level, …
  final int depth;

  /// Display label for this row (instance name or top-module name).
  final String instanceName;

  /// Module name behind this instance — shown in parentheses to the
  /// right of [instanceName].
  final String moduleName;

  /// True when the row has at least one user-defined-module child
  /// that the expand chevron can descend into.
  final bool hasChildren;

  /// Total cell count inside this scope (primitives + child instances).
  final int cellCount;
}

/// Walks the [HierarchyNode] tree starting at [HierarchyTreeState.root]
/// and produces the flattened list of rows the [ListView.builder]
/// should paint. Applies expansion + filter rules:
///
///   - A scope is included when it is the root, when the user has
///     expanded its parent (so the row is structurally visible), AND
///     when its label matches the filter — or when any descendant
///     matches, so the user sees the path that leads to the hit.
///   - The filter is case-insensitive substring against either the
///     instance name or the module name.
///   - With an empty filter, only the expand/collapse state matters.
///
/// Exposed at the top level so it's directly unit-testable without
/// pumping widgets.
List<HierarchyVisibleRow> buildVisibleRows({
  required NetlistModel model,
  required HierarchyTreeState state,
}) {
  final root = state.root;
  if (root == null) return const <HierarchyVisibleRow>[];
  final filter = state.filterText.toLowerCase();
  final rows = <HierarchyVisibleRow>[];

  bool matches(HierarchyNode node) {
    if (filter.isEmpty) return true;
    final instanceName = node.displayName.toLowerCase();
    final moduleName = node.moduleName.toLowerCase();
    return instanceName.contains(filter) || moduleName.contains(filter);
  }

  // Both walks keep an explicit stack and never enter a recursive
  // instantiation (HierarchyWalkFrame.isRecursive) or a scope past the
  // depth bound: a module that instantiates itself, filtered for a name it
  // does not contain, used to recurse until the stack overflowed. A
  // recursive instance is still listed — it is a real instance — but as a
  // leaf, since everything inside it is already inside the ancestor of the
  // same module.
  final keep = filter.isEmpty
      ? null
      : _scopesWithMatchAtOrBelow(root, model, matches);

  final path = HierarchyWalkPath();
  final stack = <HierarchyWalkFrame>[HierarchyWalkFrame.root(root)];
  while (stack.isNotEmpty && rows.length < maxHierarchyWalkScopes) {
    final frame = stack.removeLast();
    path.enter(frame);
    final node = frame.node;
    if (keep != null && keep[node] != true) continue;
    final children = frame.canDescend
        ? node.childInstanceNames(model)
        : const <String>[];
    final module = node.resolve(model);
    final cellCount = module?.cells.length ?? 0;
    rows.add(
      HierarchyVisibleRow(
        node: node,
        depth: frame.depth,
        instanceName: node.displayName,
        moduleName: node.moduleName,
        hasChildren: children.isNotEmpty,
        cellCount: cellCount,
      ),
    );
    // Expand children when the user has expanded this node OR when
    // the filter is active (so all hits are visible at once).
    final descend = state.isExpanded(node) || filter.isNotEmpty;
    if (!descend) continue;
    // Last-first, so the first child is the next row.
    for (var i = children.length - 1; i >= 0; i--) {
      final child = node.child(model, children[i]);
      if (child == null) continue;
      stack.add(path.childFrame(child));
    }
  }
  return rows;
}

/// Every scope under [root] mapped to whether it, or anything below it,
/// satisfies [matches] — what the filter needs to keep the path to a hit
/// visible. One post-order pass, so each scope is examined once, and at
/// most [maxHierarchyWalkScopes] scopes are entered; a scope past either
/// bound is judged by its own name alone.
Map<HierarchyNode, bool> _scopesWithMatchAtOrBelow(
  HierarchyNode root,
  NetlistModel model,
  bool Function(HierarchyNode node) matches,
) {
  final result = <HierarchyNode, bool>{};
  final path = HierarchyWalkPath();
  final stack = <({HierarchyWalkFrame frame, List<HierarchyNode>? children})>[
    (frame: HierarchyWalkFrame.root(root), children: null),
  ];
  var entered = 0;
  while (stack.isNotEmpty) {
    final top = stack.removeLast();
    final frame = top.frame;
    final node = frame.node;
    final children = top.children;
    if (children == null) {
      // First visit, in pre-order: queue the children, then come back to
      // this scope once they have all been judged.
      path.enter(frame);
      final expand = frame.canDescend && entered++ < maxHierarchyWalkScopes;
      final kids = <HierarchyNode>[
        if (expand)
          for (final name in node.childInstanceNames(model))
            ?node.child(model, name),
      ];
      stack.add((frame: frame, children: kids));
      for (final child in kids) {
        stack.add((frame: path.childFrame(child), children: null));
      }
      continue;
    }
    result[node] =
        matches(node) || children.any((child) => result[child] ?? false);
  }
  return result;
}
