// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core extension point through which the Pro overlay's
/// Switching Activity Heatmap publishes a per-edge color override
/// the schematic painter applies to edges (wires).
///
/// The map is keyed by [SchematicEdge.id] (a stable string the
/// graph builder emits per source-port → target-port wire); when an
/// edge id appears in the map the painter renders the wire at that
/// color *in place of* the default base paint (selection and
/// dim-overlay still win — activity coloring sits between the dim
/// pass and the selection pass).
///
/// Open-core resolves to `null` so the painter falls through to its
/// default rendering. The Pro overlay binds it to a per-tab notifier, but
/// nothing publishes into that notifier yet — publishing needs each edge's
/// hierarchical net path, which the heat-map panel does not resolve — so in
/// every shipped build the map is `null` and no wire is colored by activity.
///
/// The provider returns `null` (not an empty map) when no override
/// is active so the painter can branch off the null check rather
/// than iterating an empty map every frame.
///
/// Declared as a manual `Provider<Map<String, Color>?>` so the Pro
/// overlay overrides with `.overrideWith` without a codegen dep.
final netActivityColorOverrideProvider = Provider<Map<String, Color>?>(
  (ref) => null,
  name: 'netActivityColorOverrideProvider',
);
