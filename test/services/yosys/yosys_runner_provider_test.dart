// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/yosys_runner_provider.dart';

void main() {
  test('yosysRunnerProvider produces a YosysRunner by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final runner = container.read(yosysRunnerProvider);
    expect(runner, isA<YosysRunner>());
  });

  test('yosysRunnerProvider honors overrides', () {
    final injected = YosysRunner();
    final container = ProviderContainer(
      overrides: [yosysRunnerProvider.overrideWithValue(injected)],
    );
    addTearDown(container.dispose);
    expect(container.read(yosysRunnerProvider), same(injected));
  });
}
