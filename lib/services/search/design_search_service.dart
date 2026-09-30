// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/services/hierarchy/hierarchy_walk.dart';

/// Search modes the [DesignSearchService] supports.
enum SearchMode {
  /// Case-insensitive substring match.
  substring,

  /// Glob pattern with `*` (any chars) and `?` (single char).
  glob,

  /// Regular expression.
  regex,
}

/// Kind of element a [SearchResult] represents.
enum SearchResultKind {
  /// A user-defined-module instance (push-into target).
  instance,

  /// A cell instance (either a primitive or a module instantiation).
  cell,

  /// A named net.
  net,
}

/// One hit produced by [DesignSearchService.search].
@immutable
class SearchResult {
  /// Creates a search result.
  const SearchResult({
    required this.kind,
    required this.name,
    required this.scope,
    required this.scopeNode,
  });

  /// What kind of element this hit represents.
  final SearchResultKind kind;

  /// The matching name (instance name, cell name, or net name).
  final String name;

  /// Dotted-path of the scope that owns the element
  /// (e.g. `top.cpu.alu`).
  final String scope;

  /// The hierarchy node that owns the element. The viewer navigates
  /// to this when the user clicks the result.
  final HierarchyNode scopeNode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchResult &&
          other.kind == kind &&
          other.name == name &&
          other.scope == scope &&
          other.scopeNode == scopeNode);

  @override
  int get hashCode => Object.hash(kind, name, scope, scopeNode);

  @override
  String toString() => 'SearchResult($kind: $name @ $scope)';
}

/// Pure search service over an elaborated [NetlistModel].
///
/// Walks the entire module hierarchy and matches each instance, cell,
/// and net name against the user's query under the selected
/// [SearchMode]. Returns a flat ranked list with at most
/// [maxResults] entries — the consumer (search dialog) can paginate
/// or scroll, but we cap to keep the dialog snappy on multi-million-
/// gate designs.
class DesignSearchService {
  /// Creates a service.
  const DesignSearchService();

  /// Default cap on result count.
  static const int defaultMaxResults = 500;

  /// Runs [query] against [model] under [mode]. Empty query → empty
  /// result list.
  List<SearchResult> search({
    required NetlistModel model,
    required String query,
    SearchMode mode = SearchMode.substring,
    int maxResults = defaultMaxResults,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <SearchResult>[];
    final matcher = _matcherFor(trimmed, mode);
    if (matcher == null) return const <SearchResult>[];
    final root = HierarchyNode.rootOf(model);
    if (root == null) return const <SearchResult>[];

    final results = <SearchResult>[];
    _collect(root, model, matcher, results, maxResults);
    return results;
  }

  /// Walks the hierarchy under [root] in pre-order — the order results come
  /// back in — and collects the matches.
  ///
  /// An explicit stack rather than recursion, a recursive instantiation is
  /// never entered ([HierarchyWalkFrame.isRecursive]), and at most
  /// [maxHierarchyWalkScopes] scopes, none deeper than
  /// [maxHierarchyWalkDepth], are visited: a module that instantiates
  /// itself, searched for a name it does not contain, used to recurse until
  /// the stack overflowed.
  void _collect(
    HierarchyNode root,
    NetlistModel model,
    bool Function(String) matches,
    List<SearchResult> results,
    int maxResults,
  ) {
    final path = HierarchyWalkPath();
    final stack = <HierarchyWalkFrame>[HierarchyWalkFrame.root(root)];
    var visited = 0;
    while (stack.isNotEmpty && visited < maxHierarchyWalkScopes) {
      if (results.length >= maxResults) return;
      final frame = stack.removeLast();
      path.enter(frame);
      visited++;
      final node = frame.node;
      final module = node.resolve(model);
      if (module == null) continue;
      final scope = node.canonicalPath(model);

      // Cells (instances of either primitives or user modules).
      for (final cellName in module.cells.keys) {
        if (results.length >= maxResults) return;
        if (!matches(cellName)) continue;
        // A black-box module (a cell-library primitive) is not a scope, so
        // its instances are cells, the same way the hierarchy walks them.
        final isInstance =
            model.modules[module.cells[cellName]!.type]?.isBlackBox == false;
        results.add(
          SearchResult(
            kind: isInstance
                ? SearchResultKind.instance
                : SearchResultKind.cell,
            name: cellName,
            scope: scope,
            scopeNode: node,
          ),
        );
      }

      // Named nets.
      for (final netName in module.nets.keys) {
        if (results.length >= maxResults) return;
        if (!matches(netName)) continue;
        results.add(
          SearchResult(
            kind: SearchResultKind.net,
            name: netName,
            scope: scope,
            scopeNode: node,
          ),
        );
      }

      // Child instances, pushed last-first so the first is visited next. A
      // recursive instantiation was already reported above as a cell of this
      // scope; its contents are an ancestor's, so it is not entered.
      if (!frame.canDescend) continue;
      final children = node.childInstanceNames(model);
      for (var i = children.length - 1; i >= 0; i--) {
        final child = node.child(model, children[i]);
        if (child == null) continue;
        final childFrame = path.childFrame(child);
        if (childFrame.isRecursive) continue;
        stack.add(childFrame);
      }
    }
  }

  /// Resolves the instance name of the cell that DRIVES the named net
  /// [netName] inside [module], or `null` when the net is undriven (a
  /// module input, a constant, or purely dangling) or absent.
  ///
  /// A net result on its own has no on-canvas geometry to center — the
  /// wire is only ever drawn between the pins it connects. The natural
  /// "reveal" target for a signal is therefore the cell whose OUTPUT port
  /// drives it (e.g. clicking a register signal jumps to the flip-flop that
  /// produces it). This walks the module's cells and returns the first one
  /// with an output-direction connection carrying any of the net's bits;
  /// the returned name matches the schematic cell id / layout node id, so
  /// the caller can look up its bounds directly.
  static String? driverCellForNet(Module module, String netName) {
    final net = module.nets[netName];
    if (net == null) return null;
    final netBitIds = <int>{
      for (final bit in net.bits)
        if (bit is NetBit) bit.netId,
    };
    if (netBitIds.isEmpty) return null;
    for (final entry in module.cells.entries) {
      final cell = entry.value;
      for (final port in cell.connections.entries) {
        // Only an OUTPUT (or bidirectional) pin can drive the net.
        final direction = cell.portDirections[port.key];
        if (direction == PortDirection.input) continue;
        for (final bit in port.value) {
          if (bit is NetBit && netBitIds.contains(bit.netId)) {
            return entry.key;
          }
        }
      }
    }
    return null;
  }

  bool Function(String)? _matcherFor(String query, SearchMode mode) {
    switch (mode) {
      case SearchMode.substring:
        final lower = query.toLowerCase();
        bool matches(String name) => name.toLowerCase().contains(lower);
        return matches;
      case SearchMode.glob:
        final regex = _globToRegex(query);
        return regex.hasMatch;
      case SearchMode.regex:
        try {
          final regex = RegExp(query, caseSensitive: false);
          return regex.hasMatch;
        } on FormatException {
          return null;
        }
    }
  }

  RegExp _globToRegex(String glob) {
    final buffer = StringBuffer('^');
    for (final char in glob.split('')) {
      switch (char) {
        case '*':
          buffer.write('.*');
        case '?':
          buffer.write('.');
        case '.':
        case '+':
        case '(':
        case ')':
        case '[':
        case ']':
        case r'\':
        case r'$':
        case '|':
        case '{':
        case '}':
          buffer
            ..write(r'\')
            ..write(char);
        default:
          buffer.write(char);
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: false);
  }
}
