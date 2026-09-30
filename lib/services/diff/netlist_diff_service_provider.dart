// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/netlist_diff_service.dart';

/// Riverpod provider exposing the active [NetlistDiffService].
///
/// Open-core resolves this to [NoopNetlistDiffService] so the
/// DiffPane widget renders its empty state and the dispatch path
/// (action → service → widget) is exercised in tests without the
/// Pro overlay present. The Pro overlay registers a concrete
/// `ProNetlistDiffService` via `proOverrides`.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override it with `.overrideWith` without taking
/// the build_runner generator dep. Matches the
/// [sourcePaneServiceProvider] / [coneOfInfluenceServiceProvider] /
/// [xTraceServiceProvider] / [bookmarkAnnotationStoreProvider]
/// pattern.
final netlistDiffServiceProvider = Provider<NetlistDiffService>(
  (ref) => const NoopNetlistDiffService(),
  name: 'netlistDiffServiceProvider',
);
