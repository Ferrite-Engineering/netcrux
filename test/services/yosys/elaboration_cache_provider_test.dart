// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/elaboration_cache_provider.dart';
import 'package:netcrux/services/yosys/elaboration_cache_service.dart';

void main() {
  test('elaborationCacheServiceProvider returns a service', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(elaborationCacheServiceProvider),
      isA<ElaborationCacheService>(),
    );
  });

  test('elaborationCacheServiceProvider can be overridden', () {
    final injected = ElaborationCacheService(maxEntries: 4);
    final container = ProviderContainer(
      overrides: [
        elaborationCacheServiceProvider.overrideWithValue(injected),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(elaborationCacheServiceProvider), same(injected));
  });
}
