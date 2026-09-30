// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';

/// How the [CustomCellSymbolRegistry] resolved a lookup. Surfaces so
/// callers (renderer, manager UI) can disambiguate between an exact
/// per-project binding vs. a per-user fallback vs. a pattern / glob
/// fallback in future revisions.
enum CustomCellSymbolMatchKind {
  /// Direct, exact match on [CustomCellSymbol.moduleType].
  exactMatch,

  /// Future: wildcard / glob match — e.g. `axi_*` matched `axi_lite`.
  /// V1 implementations never emit this; reserved so callers can
  /// be coded against the eventual surface.
  patternMatch,

  /// Future: registry-wide fallback symbol applied when no specific
  /// binding exists for a module type. V1 implementations never
  /// emit this.
  wildcardFallback,
}

/// Result returned by [CustomCellSymbolRegistry.lookup]. Carries the
/// matched symbol plus how the registry resolved the lookup.
@immutable
class CustomCellSymbolMatch {
  /// Creates a registry lookup result.
  const CustomCellSymbolMatch({
    required this.symbol,
    required this.kind,
  });

  /// The symbol that was matched.
  final CustomCellSymbol symbol;

  /// How the registry resolved the lookup.
  final CustomCellSymbolMatchKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomCellSymbolMatch &&
          other.symbol == symbol &&
          other.kind == kind);

  @override
  int get hashCode => Object.hash(symbol, kind);

  @override
  String toString() =>
      'CustomCellSymbolMatch(symbol=$symbol, kind=${kind.name})';
}
