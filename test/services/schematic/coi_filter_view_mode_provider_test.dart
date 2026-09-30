// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/schematic/coi_filter_view_mode_provider.dart';

void main() {
  group('coiFilterViewModeProvider', () {
    test('default open-core value is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coiFilterViewModeProvider), isFalse);
    });

    test('override surfaces the toggled value', () {
      final container = ProviderContainer(
        overrides: <Override>[
          coiFilterViewModeProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(coiFilterViewModeProvider), isTrue);
    });
  });
}
