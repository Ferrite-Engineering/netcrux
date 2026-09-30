// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/schematic/net_activity_color_override_provider.dart';

void main() {
  group('netActivityColorOverrideProvider', () {
    test('default open-core value is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(netActivityColorOverrideProvider), isNull);
    });

    test('override returns the supplied map', () {
      final container = ProviderContainer(
        overrides: <Override>[
          netActivityColorOverrideProvider.overrideWithValue(
            <String, Color>{
              'edge-1': const Color(0xFFE74C3C),
              'edge-2': const Color(0xFF2D58D8),
            },
          ),
        ],
      );
      addTearDown(container.dispose);
      final override = container.read(netActivityColorOverrideProvider);
      expect(override, isNotNull);
      expect(override!['edge-1'], const Color(0xFFE74C3C));
      expect(override['edge-2'], const Color(0xFF2D58D8));
    });
  });
}
