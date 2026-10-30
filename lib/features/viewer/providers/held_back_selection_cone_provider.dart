// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/features/project/providers/scope_layout_gate_provider.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/services/cone_view_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'held_back_selection_cone_provider.g.dart';

/// Opens a Cone View on what the user selects while the scope on the canvas
/// is held back for being over the layout limit.
///
/// A held-back scope draws nothing, so a selection made in it (a Search
/// result, a Hierarchy filter pick, a cross-probe from a peer, the Inspector)
/// would otherwise change nothing the user can see. This puts the selection
/// on screen at once: the cone of the primary selection, fan-in, at the
/// default depth, the same cone View > Cone View opens.
///
/// Two events trigger it, because a route may select what is already
/// selected (which changes no selection): a new selection, and a reveal
/// request, which every jump-to-element route makes after selecting. Only a
/// scope that is held back at that moment is affected; under the limit, or
/// once the user approved the whole-scope layout, a selection behaves as it
/// always did. Leaving the cone with Show Whole Scope returns to the
/// held-back view and does not open the cone again until something is
/// selected again.
///
/// Scoped per tab (see `netcruxTabOverridesFactory`) and kept alive by the
/// tab content watching it.
@Riverpod(keepAlive: true)
void heldBackSelectionCone(Ref ref) {
  void openConeOnSelection() {
    if (ref.read(selectedElementProvider).isEmpty) return;
    if (!ref.read(scopeLayoutGateProvider).deferred) return;
    ConeViewController(ref.read).enter();
  }

  ref
    ..listen(selectedElementProvider, (previous, next) {
      if (next.isNotEmpty) openConeOnSelection();
    })
    ..listen(revealRequestProvider, (previous, next) {
      if (next != null) openConeOnSelection();
    });
}
