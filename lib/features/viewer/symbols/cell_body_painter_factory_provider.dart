// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/viewer/symbols/cell_body_painter_factory.dart';

/// Riverpod provider exposing the active [CellBodyPainterFactory].
///
/// Open-core resolves to [defaultCellBodyPainterFactory] — every
/// cell falls through to the built-in `painterFor(cell.kind)`. The
/// closed-source Pro overlay overrides this to a factory
/// that first consults the [CustomCellSymbolRegistry] snapshot and
/// returns an SVG-rendering painter for cells whose `type` matches a
/// registered symbol; cells without a registered symbol still fall
/// through to the built-in painter.
///
/// The provider is read by the workspace screen and threaded into
/// [SchematicCanvas] so the render object never has to talk to
/// Riverpod directly. Re-emits whenever the Pro overlay's
/// [customCellSymbolSnapshotProvider] ticks, which marks the canvas
/// for repaint via the standard render-object setter.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override with `.overrideWith` without taking the
/// build_runner generator dep. Matches the
/// [customCellSymbolRegistryProvider] /
/// [netlistDiffServiceProvider] pattern.
final cellBodyPainterFactoryProvider = Provider<CellBodyPainterFactory>(
  (ref) => defaultCellBodyPainterFactory,
  name: 'cellBodyPainterFactoryProvider',
);
