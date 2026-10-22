// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/schematic/cell_color_override_provider.dart';
import 'package:netcrux/services/schematic/net_activity_color_override_provider.dart';

void main() {
  group('cellColorOverrideProvider', () {
    test('default open-core value is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(cellColorOverrideProvider), isNull);
    });

    test('override returns the supplied map', () {
      final container = ProviderContainer(
        overrides: [
          cellColorOverrideProvider.overrideWithValue(<String, Color>{
            'ff_a': const Color(0xFFE74C3C),
          }),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(cellColorOverrideProvider), <String, Color>{
        'ff_a': const Color(0xFFE74C3C),
      });
    });

    test('is not the net map: publishing cells leaves the wires alone', () {
      final container = ProviderContainer(
        overrides: [
          cellColorOverrideProvider.overrideWithValue(<String, Color>{
            'ff_a': const Color(0xFFE74C3C),
          }),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(netActivityColorOverrideProvider), isNull);
    });
  });
}
