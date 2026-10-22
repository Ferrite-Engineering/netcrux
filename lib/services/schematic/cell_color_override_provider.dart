// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core extension point through which an overlay publishes a per-cell
/// color the schematic painter draws on the cells of the scope on screen.
///
/// The map is keyed by [SchematicCell.id], the cell's name in its module.
/// A cell the map names is drawn with a translucent fill of its color under
/// a stroked outline of the same color, on top of the cell body and the
/// wires; selection and trace overlays still show through. Both marks are
/// drawn so the color is never the only thing that sets the cell apart.
///
/// This is a seam of its own and not a reuse of
/// [netActivityColorOverrideProvider]: that map is keyed by wire, belongs to
/// the switching-activity heatmap, and fades every wire it does not name.
/// Coloring cells must not fade or recolor wires, and an overlay that owned
/// the net map would take it from the heatmap.
///
/// Open core resolves to `null`, which the painter takes as "skip the pass",
/// not as an empty map to iterate every frame.
///
/// Declared as a manual `Provider<Map<String, Color>?>` so an overlay
/// overrides it with `.overrideWith` without a codegen dependency.
final cellColorOverrideProvider = Provider<Map<String, Color>?>(
  (ref) => null,
  name: 'cellColorOverrideProvider',
);
