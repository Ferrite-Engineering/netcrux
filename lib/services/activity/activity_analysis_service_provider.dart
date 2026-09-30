// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/activity_analysis_service.dart';

/// Riverpod provider exposing the active [ActivityAnalysisService].
///
/// Open-core resolves this to [NoopActivityAnalysisService] so the
/// Switching Activity Heatmap pane renders its empty state and the
/// dispatch path is exercised in tests without the Pro overlay
/// present. The Pro overlay registers
/// `ProActivityAnalysisService` via `proOverrides`.
///
/// Declared as a manual `Provider` for the same reason as
/// [waveformSourceServiceProvider]: the Pro overlay overrides with
/// `.overrideWith` without taking a build_runner generator dep.
final activityAnalysisServiceProvider = Provider<ActivityAnalysisService>(
  (ref) => const NoopActivityAnalysisService(),
  name: 'activityAnalysisServiceProvider',
);
