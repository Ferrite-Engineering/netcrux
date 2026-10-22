// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';

/// Extension point that walks the whole cone of an element, with no depth
/// limit, for a cone view laid out at all levels. Pro feature.
///
/// The depth-limited cone views are open core and walk the graph in this
/// repository (`coneMembership`). The cone with no limit is the Cone of
/// Influence trace's own walk, so it is resolved by the Pro overlay, which
/// binds an implementation only for a licence that admits it. Open core
/// binds none, and a cone view at all levels then says it requires
/// NetCrux Pro.
abstract interface class TransitiveConeResolver {
  /// The cells, boundary ports and wires of the whole cone of [root] in
  /// [graph], walked [mode]. Never throws; an element with no connectivity
  /// yields an empty or anchor-only overlay.
  ///
  /// [graph] is a whole scope that has not been laid out: a cone view
  /// resolves its cone before any layout runs.
  Future<TraceOverlay> resolve(
    SchematicGraph graph,
    SelectedElement root,
    ConeOfInfluenceMode mode,
  );
}
