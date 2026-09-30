// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';

void main() {
  test('defaults to no manager; publishing makes it visible to readers', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final holder = container.read(tabContainerManagerHolderProvider);
    expect(holder.manager, isNull);

    final manager = TabContainerManager(
      rootContainer: container,
      overridesFactory: (_) => const [],
    );
    addTearDown(manager.dispose);
    holder.manager = manager;

    // The holder instance is stable, so a later read observes the manager.
    expect(
      container.read(tabContainerManagerHolderProvider).manager,
      same(manager),
    );
  });
}
