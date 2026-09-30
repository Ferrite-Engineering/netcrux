// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';

/// Riverpod provider exposing the active [XTraceService].
///
/// Open-core resolves this to [NoopXTraceService] so the dispatch path
/// (workspace screen → service → result panel) is exercised in tests
/// without the Pro overlay present. The Pro overlay registers a
/// `ProXTraceService` via `proOverrides`.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override it with `.overrideWith` without taking the
/// build_runner generator dep just to substitute the implementation.
/// Matches the [coneOfInfluenceServiceProvider] pattern.
final xTraceServiceProvider = Provider<XTraceService>(
  (ref) => const NoopXTraceService(),
  name: 'xTraceServiceProvider',
);
