// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';

/// Riverpod provider exposing the active [ConeOfInfluenceService].
///
/// Open-core resolves this to [NoopConeOfInfluenceService] so the
/// dispatch path (workspace screen → service → `traceOverlayProvider`)
/// is exercised in tests without the Pro overlay present. The Pro
/// overlay registers a `ProConeOfInfluenceService` via `proOverrides`.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override it with `.overrideWith` without taking the
/// build_runner generator dep just to substitute the implementation.
final coneOfInfluenceServiceProvider = Provider<ConeOfInfluenceService>(
  (ref) => const NoopConeOfInfluenceService(),
  name: 'coneOfInfluenceServiceProvider',
);
