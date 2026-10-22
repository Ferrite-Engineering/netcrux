// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cone_view_notifier.g.dart';

/// The tab's cone view: the [ConeViewRequest] the canvas lays out instead of
/// the whole scope, or null when it shows the whole scope.
///
/// A cone view belongs to the scope it was made in. Selecting another scope
/// (pushing into a cell, popping out, a breadcrumb, a search result or a
/// cross-probe elsewhere) ends it, so returning to the scope later shows the
/// whole scope again. Scoped per tab (see `netcruxTabOverridesFactory`).
@Riverpod(keepAlive: true)
class ConeViewNotifier extends _$ConeViewNotifier {
  @override
  ConeViewRequest? build() {
    ref.listen<HierarchyTreeState>(hierarchyTreeProvider, (previous, next) {
      final request = state;
      if (request != null && request.scope != next.selected) state = null;
    });
    return null;
  }

  /// Shows [request] in place of its scope's full layout.
  void show(ConeViewRequest request) {
    if (state == request) return;
    state = request;
  }

  /// Changes the walk direction of the cone on show, if any.
  void setDirection(ConeViewDirection direction) {
    final request = state;
    if (request == null || request.direction == direction) return;
    state = request.withDirection(direction);
  }

  /// Changes the depth of the cone on show, if any; null is every level.
  void setDepth(int? depth) {
    final request = state;
    if (request == null || request.depth == depth) return;
    state = request.withDepth(depth);
  }

  /// Ends the cone view: the canvas shows the whole scope again.
  void exit() {
    if (state == null) return;
    state = null;
  }
}
