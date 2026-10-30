// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'layout_approval_notifier.g.dart';

/// The scopes of this tab whose whole-scope layout the user asked for with
/// "Lay out anyway", though they hold more cells than the layout limit.
///
/// An approval belongs to the tab and lasts until the tab closes: leaving the
/// scope and coming back lays it out again without asking, and the layout
/// cache answers when the scope has not changed. It is not saved in a
/// session or a workspace, so a restored tab asks again. Scoped per tab (see
/// `netcruxTabOverridesFactory`).
@Riverpod(keepAlive: true)
class LayoutApprovalNotifier extends _$LayoutApprovalNotifier {
  @override
  Set<HierarchyNode> build() => const <HierarchyNode>{};

  /// Records that the user chose to lay [scope] out whatever its size.
  void approve(HierarchyNode scope) {
    if (state.contains(scope)) return;
    state = <HierarchyNode>{...state, scope};
  }
}
