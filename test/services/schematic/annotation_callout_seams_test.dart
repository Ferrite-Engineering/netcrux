// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/schematic/annotation_callout_seams.dart';

void main() {
  test('open core has no callout layer and no toggle: both seams are null', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(schematicCalloutLayerBuilderProvider), isNull);
    expect(container.read(toggleAnnotationCalloutsOpenerProvider), isNull);
  });

  test('the pointer claim starts released and follows its setter', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final claim = container.read(canvasOverlayGestureClaimProvider.notifier);
    expect(container.read(canvasOverlayGestureClaimProvider), isFalse);
    claim.active = true;
    expect(claim.active, isTrue);
    claim.active = false;
    expect(container.read(canvasOverlayGestureClaimProvider), isFalse);
  });

  testWidgets('an overlay supplies the toggle and it is called', (
    tester,
  ) async {
    var toggles = 0;
    late BuildContext captured;
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          toggleAnnotationCalloutsOpenerProvider.overrideWithValue(
            (_) => toggles++,
          ),
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
    capturedRef.read(toggleAnnotationCalloutsOpenerProvider)!(captured);
    expect(toggles, 1);
  });
}
