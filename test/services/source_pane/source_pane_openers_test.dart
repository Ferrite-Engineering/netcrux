// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/source_pane/source_pane_openers.dart';

void main() {
  group('source pane opener providers', () {
    test('defaults resolve to non-null no-op callbacks', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(showSourcePaneOpenerProvider), isNotNull);
      expect(container.read(openSourceForElementOpenerProvider), isNotNull);
      expect(container.read(closeSourcePaneOpenerProvider), isNotNull);
    });

    test('overrides replace the defaults', () {
      // The Pro overlay registers concrete openers via overrideWithValue;
      // assert the override path resolves correctly and returns the
      // injected reference.
      void show(_) {}
      void openFor(_, _, {dynamic elementId}) {}
      void close(_) {}

      final container = ProviderContainer(
        overrides: [
          showSourcePaneOpenerProvider.overrideWithValue(show),
          openSourceForElementOpenerProvider.overrideWithValue(openFor),
          closeSourcePaneOpenerProvider.overrideWithValue(close),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(showSourcePaneOpenerProvider), same(show));
      expect(container.read(openSourceForElementOpenerProvider), same(openFor));
      expect(container.read(closeSourcePaneOpenerProvider), same(close));
    });
  });
}
