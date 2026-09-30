// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';

/// Most scopes one walk of the instance hierarchy enters.
///
/// A hierarchy is a DAG — one module can be instantiated many times — so
/// the number of scopes can grow exponentially with depth even when the
/// file is small: thirty modules that each instantiate the next twice name
/// a billion scopes. Past this many a walk stops. The bound sits far above
/// the instance count of any design NetCrux is used on and far below the
/// point where a walk run from a keystroke would stall the window.
const int maxHierarchyWalkScopes = 65536;

/// Deepest scope a walk of the instance hierarchy enters.
///
/// Every [HierarchyNode] carries its whole instance path, so making a child,
/// hashing a node or naming its scope costs time proportional to its depth,
/// and a walk down a chain is quadratic in the chain's length: a file of
/// 100,000 modules each instantiating the next took three minutes to search
/// with the scope bound alone. Real hierarchies are tens of levels deep;
/// a scope this deep is listed but not entered.
const int maxHierarchyWalkDepth = 256;

/// One scope on an explicit-stack walk of the instance hierarchy.
///
/// The walks that use it — design search and the hierarchy panel's row
/// builder — keep their own stack instead of recursing, because recursion
/// depth would then be whatever the netlist file says it is. Frames are made
/// by a [HierarchyWalkPath], which knows the path they were reached on.
class HierarchyWalkFrame {
  /// The frame a walk starts from.
  HierarchyWalkFrame.root(this.node) : depth = 0, isRecursive = false;

  HierarchyWalkFrame._(this.node, this.depth, {required this.isRecursive});

  /// The scope this frame visits.
  final HierarchyNode node;

  /// Levels below the root.
  final int depth;

  /// Whether [node] instantiates a module that is already open on the path
  /// above it — a module that, directly or through others, contains
  /// itself.
  ///
  /// Yosys never elaborates such a design, but NetCrux also opens netlist
  /// JSON directly, and a file that does it describes an infinite
  /// hierarchy: every lap of the cycle is a fresh [HierarchyNode] (its path
  /// is one instance longer), so a walk that only remembers the nodes it has
  /// seen never recognises a repeat. The module name is what repeats. A
  /// recursive scope is still a real instance and is reported as one; a walk
  /// just does not enter it, since everything inside it is already inside
  /// the ancestor of the same module.
  final bool isRecursive;

  /// Whether a walk may enter this scope's children: it is not a recursive
  /// instantiation and is above [maxHierarchyWalkDepth].
  bool get canDescend => !isRecursive && depth < maxHierarchyWalkDepth;
}

/// The module names open on the path to the scope a pre-order walk is in.
///
/// A walk calls [enter] on each frame as it takes it off its stack, and
/// makes the frames for that scope's children with [childFrame]. Because
/// frames are entered in pre-order, the path held here is always exactly
/// the entered frame's ancestors plus itself, so [childFrame] answers
/// [HierarchyWalkFrame.isRecursive] in constant time — a check that walked
/// up the ancestors instead would make a deep hierarchy quadratic.
class HierarchyWalkPath {
  final List<String> _modules = <String>[];
  final Map<String, int> _open = <String, int>{};

  /// Makes [frame] the scope the walk is in, closing every scope on the
  /// current path at its depth or below.
  void enter(HierarchyWalkFrame frame) {
    while (_modules.length > frame.depth) {
      final closed = _modules.removeLast();
      final count = _open[closed]! - 1;
      if (count == 0) {
        _open.remove(closed);
      } else {
        _open[closed] = count;
      }
    }
    final module = frame.node.moduleName;
    _modules.add(module);
    _open[module] = (_open[module] ?? 0) + 1;
  }

  /// A frame for [child], an instance inside the scope last [enter]ed.
  HierarchyWalkFrame childFrame(HierarchyNode child) => HierarchyWalkFrame._(
    child,
    _modules.length,
    isRecursive: _open.containsKey(child.moduleName),
  );
}
