// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/bookmark_annotation_store.dart';

/// Riverpod provider exposing the active [BookmarkAnnotationStore].
///
/// Open-core resolves this to [NoopBookmarkAnnotationStore] so the
/// dispatch path (Pro panel → store → snapshot provider) is
/// exercised in tests without the Pro overlay present. The Pro
/// overlay registers an `InSessionBookmarkAnnotationStore` via
/// `proOverrides`.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override it with `.overrideWith` without taking the
/// build_runner generator dep. Matches the
/// [coneOfInfluenceServiceProvider] / [xTraceServiceProvider] pattern.
final bookmarkAnnotationStoreProvider = Provider<BookmarkAnnotationStore>(
  (ref) => const NoopBookmarkAnnotationStore(),
  name: 'bookmarkAnnotationStoreProvider',
);

/// Convenience provider exposing the current snapshot the panel
/// widgets `ref.watch`. The Pro panel widgets read this rather than
/// calling `snapshot()` directly so they receive automatic rebuilds
/// when the store's notifier-backed snapshot changes.
///
/// Open-core's no-op store returns the same empty snapshot every time
/// so this provider also resolves to empty under the default — but
/// the call site code path is identical, which is the point of the
/// open-core seam.
final bookmarkAnnotationSnapshotProvider = Provider<BookmarkAnnotationSnapshot>(
  (ref) {
    final store = ref.watch(bookmarkAnnotationStoreProvider);
    return store.snapshot();
  },
  name: 'bookmarkAnnotationSnapshotProvider',
);
