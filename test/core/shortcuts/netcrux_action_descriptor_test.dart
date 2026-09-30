// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptor.dart';

void main() {
  test('defaults: no surfaces, always visible, always enabled', () {
    const descriptor = NetcruxActionDescriptor();
    const ctx = NetcruxActionContext();
    expect(descriptor.surfaces, isEmpty);
    expect(descriptor.isVisible(ctx), isTrue);
    expect(descriptor.isEnabled(ctx), isTrue);
  });

  test('custom predicates are honored', () {
    final descriptor = NetcruxActionDescriptor(
      surfaces: const {NetcruxActionSurface.menu},
      isVisible: (c) => c.hasOpenTab,
      isEnabled: (c) => c.hasNetlist,
    );
    const empty = NetcruxActionContext();
    const loaded = NetcruxActionContext(hasOpenTab: true, hasNetlist: true);
    expect(descriptor.isVisible(empty), isFalse);
    expect(descriptor.isEnabled(empty), isFalse);
    expect(descriptor.isVisible(loaded), isTrue);
    expect(descriptor.isEnabled(loaded), isTrue);
    expect(descriptor.surfaces, {NetcruxActionSurface.menu});
  });
}
