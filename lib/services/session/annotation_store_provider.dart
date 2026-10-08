// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/annotation_store.dart';
import 'package:netcrux/services/session/annotation_state.dart';
import 'package:netcrux/services/session/in_session_annotation_store.dart';

/// Riverpod provider exposing the active [AnnotationStore].
///
/// Resolves to an [InSessionAnnotationStore] over
/// [annotationStateProvider]. A design's annotations
/// belong to the tab it is open in, so the per-tab override list re-binds
/// this provider, the state it writes and the snapshot below together; the
/// root-scope instance serves callers with no tab (a test harness, a
/// session loaded before any tab exists).
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so an embedder
/// can override it with `.overrideWith` without taking the build_runner
/// generator dependency. Matches the [coneOfInfluenceServiceProvider] /
/// [xTraceServiceProvider] pattern.
final annotationStoreProvider = Provider<AnnotationStore>(
  InSessionAnnotationStore.new,
  name: 'annotationStoreProvider',
);

/// Convenience provider exposing the current snapshot the panel widgets
/// `ref.watch`. Derived from [annotationStateProvider] rather than
/// from `store.snapshot()` so the widgets rebuild on every mutation.
final annotationSnapshotProvider = Provider<AnnotationSnapshot>(
  (ref) => ref.watch(annotationStateProvider),
  name: 'annotationSnapshotProvider',
);
