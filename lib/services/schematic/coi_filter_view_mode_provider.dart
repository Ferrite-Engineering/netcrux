// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core extension point for the Cone of Influence "filter view"
/// hide-mode toggle.
///
/// When `false` (open-core default) the schematic painter dims non-
/// highlighted elements while the COI [TraceOverlay] is active — the
/// default behavior. When `true`, the painter skips
/// non-highlighted elements entirely, producing a focused view of
/// just the COI sub-graph.
///
/// The toggle is consumed by `SchematicCanvas` / `SchematicCanvas­
/// RenderObject` (rendering layer) and surfaced by the Pro overlay
/// in the COI action bar / command palette. Open-core resolves to
/// `false` so the canvas paints normally without the Pro overlay
/// present; the Pro overlay registers a `StateProvider<bool>` via
/// `proOverrides` whose value is bound to the user-facing toggle.
///
/// Declared as a manual `Provider<bool>` (not `@Riverpod`-codegen)
/// so the Pro overlay can override it with `.overrideWith` without
/// taking the build_runner generator dep. Matches the
/// [coneOfInfluenceServiceProvider] /
/// [netActivityColorOverrideProvider] pattern.
final coiFilterViewModeProvider = Provider<bool>(
  (_) => false,
  name: 'coiFilterViewModeProvider',
);
