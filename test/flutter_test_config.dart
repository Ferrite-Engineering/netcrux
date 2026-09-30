// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tolerant_golden_comparator.dart';

/// Test bootstrap. Installs a golden comparator that tolerates a tiny amount
/// of per-pixel difference.
///
/// Golden images are committed from one environment but validated across the
/// Linux / macOS / Windows CI matrix, where font hinting and anti-aliasing
/// differ by a few edge pixels (observed: 0.06–0.09% on the schematic
/// goldens). A strict byte-exact comparator fails on that cosmetic variance.
/// A small [_kGoldenTolerance] absorbs it while still catching real visual
/// regressions (which move far more than half a percent of pixels).
const double _kGoldenTolerance = 0.005; // 0.5%

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The welcome screen's CruxGlowingAppIcon runs perpetual
  // AnimationController.repeat loops; without this, any test that renders
  // the empty-canvas route can never pumpAndSettle.
  CruxGlowingAppIcon.debugDisableAnimations = true;

  // [ModalGuard] is process-global re-entrancy state for exclusive modal
  // surfaces. A widget test that pumps a guarded dialog open and tears down
  // without dismissing it leaves its key set, which would suppress the next
  // test's open. Reset before every test for isolation.
  setUp(ModalGuard.reset);

  // File-backed on the VM; a no-op when compiled for the browser, which has
  // no golden files and no `LocalFileComparator`.
  installTolerantGoldenComparator(_kGoldenTolerance);
  await testMain();
}
