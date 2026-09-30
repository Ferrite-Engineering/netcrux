// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/source_pane_service.dart';

/// Riverpod provider exposing the active [SourcePaneService].
///
/// Open-core resolves this to [NoopSourcePaneService] so the
/// SourcePane widget renders an empty state and the dispatch path
/// (action → service → widget) is exercised in tests without the Pro
/// overlay present. The Pro overlay registers a
/// `ProSourcePaneService` via `proOverrides`.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override it with `.overrideWith` without taking
/// the build_runner generator dep. Matches the
/// [coneOfInfluenceServiceProvider] / [xTraceServiceProvider] /
/// [bookmarkAnnotationStoreProvider] /
/// [schematicContextMenuExtensionsProvider] pattern.
final sourcePaneServiceProvider = Provider<SourcePaneService>(
  (ref) => const NoopSourcePaneService(),
  name: 'sourcePaneServiceProvider',
);
