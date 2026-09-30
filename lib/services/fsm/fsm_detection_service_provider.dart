// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/fsm_detection_service.dart';

/// Riverpod provider exposing the active [FsmDetectionService].
///
/// Open-core resolves this to [NoopFsmDetectionService] so the
/// [FsmBubbleDiagramPane] widget renders its empty state and the
/// dispatch path (action → service → widget) is exercised in tests
/// without the Pro overlay present. The Pro overlay registers a
/// concrete `ProFsmDetectionService` via `proOverrides`.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override it with `.overrideWith` without taking
/// the build_runner generator dep. Matches the
/// [netlistDiffServiceProvider] / [sourcePaneServiceProvider] /
/// [coneOfInfluenceServiceProvider] / [xTraceServiceProvider]
/// pattern.
final fsmDetectionServiceProvider = Provider<FsmDetectionService>(
  (ref) => const NoopFsmDetectionService(),
  name: 'fsmDetectionServiceProvider',
);
