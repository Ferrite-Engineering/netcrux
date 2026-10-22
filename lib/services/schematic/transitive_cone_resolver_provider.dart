// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/transitive_cone_resolver.dart';

/// The [TransitiveConeResolver] a cone view at all levels walks with, or
/// null when this build or licence has none.
///
/// Open core resolves to null: the depth-limited cone views are open core,
/// the cone with no limit is Pro. The Pro overlay overrides this provider
/// and owns its gate: its override watches the licence tier and the beta
/// period and yields a resolver only when they admit the Pro form.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the Pro
/// overlay can override it with `.overrideWith`, matching
/// `coneOfInfluenceServiceProvider`.
final transitiveConeResolverProvider = Provider<TransitiveConeResolver?>(
  (ref) => null,
  name: 'transitiveConeResolverProvider',
);
