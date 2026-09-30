// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';

void main() {
  test('open core reports no Pro overlay; an override installs one', () {
    final openCore = ProviderContainer();
    addTearDown(openCore.dispose);
    expect(openCore.read(proOverlayInstalledProvider), isFalse);

    final pro = ProviderContainer(
      overrides: [proOverlayInstalledProvider.overrideWithValue(true)],
    );
    addTearDown(pro.dispose);
    expect(pro.read(proOverlayInstalledProvider), isTrue);
  });
}
