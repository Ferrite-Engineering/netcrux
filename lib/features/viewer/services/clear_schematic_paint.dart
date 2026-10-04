// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:netcrux/features/cdc/providers/cdc_analysis_state_provider.dart';
import 'package:netcrux/features/reset_domain/providers/reset_domain_analysis_state_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';

/// Reads a provider: `ref.read` or `container.read`, torn off.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// What one press of Escape (`NetcruxAction.clearOverlay`) clears, in the
/// tab [read] resolves: the schematic selection, the fanin / fanout trace
/// overlay, and the focused CDC and reset-domain crossings whose paint the
/// crossing overlay draws.
///
/// One press clears all of them. They are all highlights drawn over the
/// same schematic, and a layered Escape would make what one press does
/// depend on state the user cannot see. The narrower clear actions (Clear
/// Cone of Influence, Clear CDC Analysis Selection, Clear Reset Analysis
/// Selection) remain for clearing one of them alone. The analysis results,
/// the panels and their filters are left as they are.
///
/// Shared by the keyboard dispatcher (the rebindable `clearOverlay`
/// action) and the schematic canvas's own Escape handler, so the two can
/// never drift.
void clearSchematicPaint(ProviderReader read) {
  read(selectedElementProvider.notifier).clear();
  read(traceOverlayProvider.notifier).clear();
  read(cdcAnalysisStateProvider.notifier).clearSelection();
  read(resetDomainAnalysisStateProvider.notifier).clearSelection();
}
