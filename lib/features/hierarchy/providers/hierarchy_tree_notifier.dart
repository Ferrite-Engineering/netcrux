// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'hierarchy_tree_notifier.g.dart';

/// Immutable snapshot of the hierarchy browser's UI state.
///
/// The notifier rebuilds this object on every state change; widgets
/// `ref.watch` the provider and re-render against the new state.
@immutable
class HierarchyTreeState {
  /// Creates a [HierarchyTreeState].
  const HierarchyTreeState({
    required this.model,
    required this.root,
    required this.selected,
    required this.expandedKeys,
    required this.filterText,
  });

  /// Empty default — no design loaded. Used as the initial state of
  /// [HierarchyTreeNotifier] before [HierarchyTreeNotifier.setModel]
  /// is called.
  static const HierarchyTreeState empty = HierarchyTreeState(
    model: null,
    root: null,
    selected: null,
    expandedKeys: <String>{},
    filterText: '',
  );

  /// Loaded design, or `null` before [HierarchyTreeNotifier.setModel].
  final NetlistModel? model;

  /// Root [HierarchyNode] derived from [model], or `null` when the
  /// model has no top module.
  final HierarchyNode? root;

  /// Currently selected scope, or `null` when nothing is selected.
  /// Distinct from [root]: a freshly loaded design has [root] populated
  /// but [selected] equal to the root only after the notifier
  /// promotes it (the schematic canvas reads [selected]).
  final HierarchyNode? selected;

  /// Set of [_keyOf] expansion keys (one per expanded scope).
  /// Membership means "this scope is expanded in the tree view"; the
  /// keys are derived from `HierarchyNode.path` so they're stable
  /// across notifier rebuilds.
  final Set<String> expandedKeys;

  /// Case-insensitive substring used by the panel to filter the
  /// rendered tree. Empty means "no filter — show everything".
  final String filterText;

  /// True when the scope at [node]'s path is currently expanded.
  bool isExpanded(HierarchyNode node) => expandedKeys.contains(_keyOf(node));

  /// True when [node] equals [selected]. Tolerates `null` [selected].
  bool isSelected(HierarchyNode node) => selected == node;

  /// Returns a copy with the given fields replaced.
  HierarchyTreeState copyWith({
    NetlistModel? model,
    HierarchyNode? root,
    HierarchyNode? selected,
    Set<String>? expandedKeys,
    String? filterText,
    bool clearSelection = false,
  }) {
    return HierarchyTreeState(
      model: model ?? this.model,
      root: root ?? this.root,
      selected: clearSelection ? null : (selected ?? this.selected),
      expandedKeys: expandedKeys ?? this.expandedKeys,
      filterText: filterText ?? this.filterText,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HierarchyTreeState) return false;
    if (other.model != model) return false;
    if (other.root != root) return false;
    if (other.selected != selected) return false;
    if (other.filterText != filterText) return false;
    if (other.expandedKeys.length != expandedKeys.length) return false;
    for (final key in expandedKeys) {
      if (!other.expandedKeys.contains(key)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    model,
    root,
    selected,
    filterText,
    Object.hashAllUnordered(expandedKeys),
  );
}

/// Canonical expansion-key string for a [HierarchyNode]. Used as the
/// element type of [HierarchyTreeState.expandedKeys]. Keys must be
/// stable across notifier rebuilds; `HierarchyNode.path` joined by
/// `/` (an instance-name-illegal character) is sufficient.
String _keyOf(HierarchyNode node) => node.path.join('/');

/// Per-design hierarchy-browser state.
///
/// Holds the elaborated [NetlistModel] plus the UI state (which scope
/// is selected, which scopes are expanded, the active filter string)
/// that the hierarchy panel binds to. Mirrors WaveCrux's pattern: a
/// thin Riverpod notifier whose methods feature code calls; the panel
/// widget itself is dumb and just renders the resulting
/// [HierarchyTreeState].
///
/// Scoped per-tab: `netcruxTabOverridesFactory` re-binds this provider
/// in every tab's `ProviderContainer`, so each open design has its own
/// selection, expansion set, and filter. Consumers read the same
/// provider name and resolve whichever instance their container owns;
/// a read that hoists to the root container sees an empty tree.
@Riverpod(keepAlive: true)
class HierarchyTreeNotifier extends _$HierarchyTreeNotifier {
  @override
  HierarchyTreeState build() => HierarchyTreeState.empty;

  /// Loads [model] into the notifier. Resets the expanded set to "just
  /// the root expanded" and selects the root (when [model] has one)
  /// so the schematic canvas has something to render immediately.
  void setModel(NetlistModel? model) {
    if (model == null) {
      state = HierarchyTreeState.empty;
      return;
    }
    final root = HierarchyNode.rootOf(model);
    state = HierarchyTreeState(
      model: model,
      root: root,
      selected: root,
      expandedKeys: root == null ? const <String>{} : <String>{_keyOf(root)},
      filterText: '',
    );
  }

  /// Expands the scope at [node]. No-op when there is no model or the
  /// scope is already expanded.
  void expandScope(HierarchyNode node) {
    if (state.model == null) return;
    final key = _keyOf(node);
    if (state.expandedKeys.contains(key)) return;
    state = state.copyWith(
      expandedKeys: <String>{...state.expandedKeys, key},
    );
  }

  /// Collapses the scope at [node]. The root cannot be collapsed —
  /// collapsing it would erase the entire tree and is purely a UI
  /// no-op in practice; the call is silently ignored. No-op when
  /// there is no model or the scope is already collapsed.
  void collapseScope(HierarchyNode node) {
    if (state.model == null) return;
    if (node.isRoot) return;
    final key = _keyOf(node);
    if (!state.expandedKeys.contains(key)) return;
    final next = <String>{...state.expandedKeys}..remove(key);
    state = state.copyWith(expandedKeys: next);
  }

  /// Toggles the expansion state of the scope at [node]. Useful for
  /// chevron clicks where the widget doesn't have to compute the
  /// current state itself.
  void toggleScope(HierarchyNode node) {
    if (state.model == null) return;
    if (state.isExpanded(node)) {
      collapseScope(node);
    } else {
      expandScope(node);
    }
  }

  /// Sets [node] as the currently selected scope. The schematic canvas
  /// observes [HierarchyTreeState.selected] and re-renders. No-op
  /// when there is no model loaded or [node] is already selected.
  ///
  /// Selecting a deep scope also expands every ancestor so the
  /// selection is visible in the tree. The root itself is always
  /// expanded by [setModel].
  void selectScope(HierarchyNode node) {
    if (state.model == null) return;
    if (state.selected == node) return;
    final expanded = <String>{...state.expandedKeys};
    for (var depth = 0; depth < node.path.length; depth++) {
      final ancestorPath = node.path.sublist(0, depth);
      expanded.add(ancestorPath.join('/'));
    }
    state = state.copyWith(selected: node, expandedKeys: expanded);
  }

  /// Makes [keys] the expanded scopes — a saved session's rows — while
  /// keeping the root and every ancestor of the selected scope expanded, so
  /// the selection stays visible. Keys that name no scope of this model are
  /// harmless: membership is all a key does. No-op when there is no model.
  void restoreExpanded(Iterable<String> keys) {
    if (state.model == null) return;
    final expanded = <String>{...keys};
    final root = state.root;
    if (root != null) expanded.add(_keyOf(root));
    final selected = state.selected;
    if (selected != null) {
      for (var depth = 0; depth < selected.path.length; depth++) {
        expanded.add(selected.path.sublist(0, depth).join('/'));
      }
    }
    state = state.copyWith(expandedKeys: expanded);
  }

  /// Sets the filter substring. Trimmed; an empty string clears the
  /// filter. The filter is purely a display affordance — it does not
  /// touch [HierarchyTreeState.selected].
  ///
  /// Named `setFilterText` (not `filterText`) so the method does not
  /// shadow [HierarchyTreeState.filterText] when callers read both
  /// off the same provider container.
  void setFilterText(String value) {
    final trimmed = value.trim();
    if (trimmed == state.filterText) return;
    state = state.copyWith(filterText: trimmed);
  }

  /// Pushes into the child instance named [instanceName] inside the
  /// currently [HierarchyTreeState.selected] scope. No-op if there is no
  /// current selection, no model, or the named child does not resolve
  /// (e.g. it's a primitive cell, not a user-defined module).
  ///
  /// Wired to the schematic canvas's double-click-on-instance gesture.
  void pushInto(String instanceName) {
    final model = state.model;
    final current = state.selected;
    if (model == null || current == null) return;
    final child = current.child(model, instanceName);
    if (child == null) return;
    selectScope(child);
    // The "is drill-down navigation the core loop?" counter. Deliberately
    // only on `pushInto`: `selectScope` is also how a search hit, a breadcrumb
    // click and a CXP cross-probe move the view, and those are not the user
    // walking down the hierarchy. The event carries no properties at all —
    // `instanceName` is design data and never leaves the machine (the
    // never-collect list, `https://edacrux.app/telemetry`).
    ref
        .read(telemetryServiceProvider)
        .record(TelemetryEvent('schematic.scope_pushed'));
  }

  /// Pops out to the parent scope of the current
  /// [HierarchyTreeState.selected] node. No-op when already at the root
  /// or there is no model loaded.
  ///
  /// Wired to the schematic canvas's double-click-on-empty-area
  /// gesture and to the Backspace / Cmd+[ / Ctrl+[ shortcut.
  void popOut() {
    final model = state.model;
    final current = state.selected;
    if (model == null || current == null) return;
    final parent = current.parent(model);
    if (parent == null) return;
    selectScope(parent);
  }

  /// Walks to the node whose path matches [path] exactly. The walk
  /// starts at the top module and resolves each segment as an instance
  /// name. Used by the breadcrumb widget — clicking a segment computes
  /// the prefix path and hands it here so the notifier can swap the
  /// selection in one atomic update.
  ///
  /// No-op when [path] does not resolve (a stale link from a session
  /// that's been re-elaborated, etc.).
  void selectByPath(List<String> path) {
    final model = state.model;
    if (model == null) return;
    final root = HierarchyNode.rootOf(model);
    if (root == null) return;
    var node = root;
    for (final segment in path) {
      final next = node.child(model, segment);
      if (next == null) return;
      node = next;
    }
    selectScope(node);
  }
}
