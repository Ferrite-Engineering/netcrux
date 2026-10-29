// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/schematic/exported_cell_symbol.dart';

/// Riverpod provider exposing the active [CellSymbolSvgSource]: the custom
/// symbol artwork Save as SVG writes for a cell, the export's counterpart
/// of `cellBodyPainterFactoryProvider`.
///
/// Open core resolves to [noCellSymbolSvg]: every cell exports its built-in
/// symbol. An overlay that registers custom symbols overrides it to return
/// the same artwork its canvas painter draws.
///
/// A manual `Provider` (not `@Riverpod`-codegen) so an overlay can override
/// it with `.overrideWith` without the build_runner generator dependency.
final cellSymbolSvgSourceProvider = Provider<CellSymbolSvgSource>(
  (ref) => noCellSymbolSvg,
  name: 'cellSymbolSvgSourceProvider',
);
