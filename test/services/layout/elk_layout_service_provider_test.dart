// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';

void main() {
  test('elkLayoutServiceProvider returns a service', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(elkLayoutServiceProvider), isA<ElkLayoutService>());
  });

  test('elkLayoutServiceProvider can be overridden', () {
    final injected = ElkLayoutService(
      hostFactory: () => throw UnimplementedError(),
      assetLoader: (_) async => '',
    );
    final container = ProviderContainer(
      overrides: [elkLayoutServiceProvider.overrideWithValue(injected)],
    );
    addTearDown(container.dispose);
    expect(container.read(elkLayoutServiceProvider), same(injected));
  });
}
