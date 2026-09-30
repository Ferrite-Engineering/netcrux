// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/clock_domain_analysis_service.dart';

/// Riverpod provider exposing the active [ClockDomainAnalysisService].
///
/// Open-core resolves this to [NoopClockDomainAnalysisService] so the
/// [CdcAnalysisPane] widget renders its empty state and the dispatch
/// path (action → service → widget) is exercised in tests without the
/// Pro overlay present. The Pro overlay registers a concrete
/// `ProClockDomainAnalysisService` via `proOverrides`.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override it with `.overrideWith` without taking the
/// build_runner generator dep. Matches the
/// [fsmDetectionServiceProvider] / [netlistDiffServiceProvider]
/// pattern.
final clockDomainAnalysisServiceProvider = Provider<ClockDomainAnalysisService>(
  (ref) => const NoopClockDomainAnalysisService(),
  name: 'clockDomainAnalysisServiceProvider',
);
