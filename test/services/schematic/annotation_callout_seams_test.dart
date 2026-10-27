// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/schematic/annotation_callout_seams.dart';

void main() {
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
}
