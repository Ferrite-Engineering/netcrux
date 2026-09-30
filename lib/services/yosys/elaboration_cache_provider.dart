// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/yosys/elaboration_cache_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'elaboration_cache_provider.g.dart';

/// The single [ElaborationCacheService] used by the elaboration
/// pipeline. `keepAlive` so cached entries survive across the lifetimes
/// of individual project widgets — re-opening a project should be
/// instant.
@Riverpod(keepAlive: true)
ElaborationCacheService elaborationCacheService(Ref ref) =>
    ElaborationCacheService();
