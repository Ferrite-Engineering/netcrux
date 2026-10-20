// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/remote/cxp/cxp_selection_resolver.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';

/// Subscribes to a [`ProviderContainer`]'s [`selectedElementProvider`] and
/// broadcasts [`NotifySelection`] to every CXP peer subscribed to the
/// kind whenever the primary selection changes.
///
/// Pure listener — no widgets, no `WidgetRef`. Built so it can be
/// driven from either a [`ConsumerStatefulWidget`] (the production case
/// where the active-tab `ProviderContainer` is supplied by
/// [`ActiveTabScope`]) or directly from a test that constructs a
/// container with overridden providers.
///
/// Emission policy mirrors what the spec calls out:
///
/// - Empty selection ([SelectedElementNone]) is not broadcast — peers
///   cannot do anything useful with "nothing selected," and suppression
///   avoids churn from canvas background clicks.
/// - Multi-select emits only the primary element. A future protocol
///   extension may broadcast the full list.
/// - Emission is gated on the shared runtime: with the server off, or the
///   "Broadcast selection" setting off, `broadcastCruxCxpSelection` sends
///   nothing.
class CxpOutboundEmitterController {
  /// Attaches the listener to [container] and starts forwarding.
  CxpOutboundEmitterController(this._container) {
    _subscription = _container.listen<Selection>(
      selectedElementProvider,
      _onSelectionChanged,
    );
  }

  final ProviderContainer _container;
  late final ProviderSubscription<Selection> _subscription;

  /// Stop forwarding. Idempotent.
  void dispose() {
    _subscription.close();
  }

  void _onSelectionChanged(Selection? previous, Selection next) {
    final element = next.primary;
    if (element is SelectedElementNone) return;

    final tree = _container.read(hierarchyTreeProvider);
    final resolved = resolveCxpSelection(
      element: element,
      model: tree.model,
      scope: tree.selected,
    );
    if (resolved == null) return;

    // Tag every automatic broadcast with the shared design id so a
    // receiver that cannot resolve the element locally can still open the
    // right artifact via its workspace manifest. Null-aware: dropped when no
    // design is loaded.
    final designId = cxpDesignIdForProject(
      _container.read(currentProjectProvider),
    );
    // The user gate ("Broadcast selection automatically") and the server being
    // up are the shared broadcast's: it sends nothing when either is off.
    // Explicit sends ("Cross-probe to", "Open in WaveCrux") bypass this
    // controller and still work.
    broadcastCruxCxpSelection(
      _container.read,
      resolved.toNotifySelection(<String, Object?>{
        cxpDesignIdMetadataKey: ?designId,
      }),
    );
  }
}
