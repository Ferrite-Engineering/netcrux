// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/schematic/scope_layout_gate.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';
import 'package:netcrux/features/viewer/providers/layout_approval_notifier.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'scope_layout_gate_provider.g.dart';

/// Whether the scope on the tab's canvas is laid out now or waits for the
/// user.
///
/// Reads one number from the model, the scope's cell count, so deciding costs
/// nothing however large the design is. The layout pipeline
/// (`currentLaidOutGraphProvider`) consults it before it builds the schematic
/// graph or the layout input, and the canvas consults it to say why nothing
/// is drawn. A scope shown as a cone view is never held back, and a scope the
/// user approved is laid out whatever its size.
///
/// Scoped per tab (see `netcruxTabOverridesFactory`): it reads the tab's
/// model, selection and cone view.
@Riverpod(keepAlive: true)
ScopeLayoutGate scopeLayoutGate(Ref ref) {
  final model = ref.watch(loadedNetlistProvider).value;
  final node = ref.watch(hierarchyTreeProvider).selected;
  final limit =
      ref.watch(appSettingsProvider).value?.layoutCellLimit ??
      kDefaultLayoutCellLimit;
  if (model == null || node == null) {
    return ScopeLayoutGate(cellCount: 0, limit: limit);
  }
  final module = node.resolve(model);
  if (module == null) return ScopeLayoutGate(cellCount: 0, limit: limit);
  final cone = ref.watch(coneViewProvider);
  return ScopeLayoutGate(
    cellCount: module.cells.length,
    limit: limit,
    approved: ref.watch(layoutApprovalProvider).contains(node),
    inCone: cone != null && cone.scope == node,
  );
}
