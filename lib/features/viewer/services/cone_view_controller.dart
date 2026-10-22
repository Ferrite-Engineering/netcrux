// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/services/clear_schematic_paint.dart';

/// Enters, adjusts and leaves the cone view of the tab [ProviderReader]
/// reads: the one funnel the View menu, the command palette, the schematic
/// context menu and the cone-view bar all go through.
///
/// The tier gate for the cone with no depth limit is the caller's: this
/// runs once activation is permitted.
class ConeViewController {
  /// Creates a controller over the tab [_read] resolves.
  const ConeViewController(this._read);

  final ProviderReader _read;

  /// Lays out the cone of [root], or of the primary selection when [root]
  /// is null, in place of the scope. With nothing to grow from, the root of
  /// the cone already on show is kept, so changing the form of a cone needs
  /// no selection.
  ///
  /// A cone already on show in this scope lends its direction and, unless
  /// [transitive] or it was unlimited, its depth. [transitive] asks for
  /// every level (the Pro form). A trace overlay is cleared: its ids belong
  /// to the layout being replaced.
  ///
  /// Returns false when there is no scope or nothing to grow from.
  bool enter({SelectedElement? root, bool transitive = false}) {
    final scope = _read(hierarchyTreeProvider).selected;
    if (scope == null) return false;
    final current = _read(coneViewProvider);
    final previous = current != null && current.scope == scope ? current : null;
    final selected = root ?? _read(selectedElementProvider).primary;
    final start = selected.isNone ? previous?.root : selected;
    if (start == null) return false;
    final direction = previous?.direction ?? ConeViewDirection.fanIn;
    final request = ConeViewRequest(
      scope: scope,
      root: start,
      direction: direction,
      depth: transitive ? null : previous?.depth ?? kDefaultConeViewDepth,
    );
    if (root != null) _read(selectedElementProvider.notifier).select(root);
    _read(traceOverlayProvider.notifier).clear();
    _read(coneViewProvider.notifier).show(request);
    _read(telemetryServiceProvider).record(
      TelemetryEvent(
        'cone_view.opened',
        properties: <String, Object?>{
          'direction': telemetryEnumToken(direction),
          'form': transitive ? 'transitive' : 'limited',
        },
      ),
    );
    return true;
  }

  /// Changes the depth of the cone on show; null is every level, which the
  /// caller gates.
  void setDepth(int? depth) {
    _read(traceOverlayProvider.notifier).clear();
    _read(coneViewProvider.notifier).setDepth(depth);
  }

  /// Changes the walk direction of the cone on show.
  void setDirection(ConeViewDirection direction) {
    _read(traceOverlayProvider.notifier).clear();
    _read(coneViewProvider.notifier).setDirection(direction);
  }

  /// Shows the whole scope again, framing the cone's root in it unless
  /// something else already asked to be revealed. The selection is kept.
  void exit() {
    final current = _read(coneViewProvider);
    if (current == null) return;
    final target = revealTargetOf(
      current.root,
      _read(currentLaidOutGraphProvider).value?.graph,
    );
    _read(traceOverlayProvider.notifier).clear();
    _read(coneViewProvider.notifier).exit();
    if (target != null && _read(revealRequestProvider) == null) {
      _read(revealRequestProvider.notifier).request(target);
    }
  }

  /// The layout node that stands for [root]: its cell, its boundary port,
  /// or the cell that drives a wire (looked up in [graph]); null when
  /// there is none to frame.
  static String? revealTargetOf(SelectedElement root, SchematicGraph? graph) {
    switch (root) {
      case SelectedElementNone():
        return null;
      case SelectedElementCell(:final cellId):
        return cellId;
      case SelectedElementPort(:final cellId):
        return cellId;
      case SelectedElementBoundaryPort(:final portId):
        return portId;
      case SelectedElementWire(:final edgeId):
        final edge = graph?.findEdge(edgeId);
        if (edge == null) return null;
        return edge.sourcePortId.startsWith('port:')
            ? edge.sourcePortId
            : cellIdOfPinId(edge.sourcePortId);
    }
  }
}
