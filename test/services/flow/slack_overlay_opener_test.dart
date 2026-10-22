// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/flow/slack_overlay_opener.dart';

void main() {
  test('open core has no overlay opener: the seam is null', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(toggleSlackOverlayOpenerProvider), isNull);
  });

  testWidgets('an overlay supplies the opener and it is called', (
    tester,
  ) async {
    var toggles = 0;
    late BuildContext captured;
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          toggleSlackOverlayOpenerProvider.overrideWithValue((_) => toggles++),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              captured = context;
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    capturedRef.read(toggleSlackOverlayOpenerProvider)!(captured);
    expect(toggles, 1);
  });
}
