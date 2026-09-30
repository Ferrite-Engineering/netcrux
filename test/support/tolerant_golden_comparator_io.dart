// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replaces the default [LocalFileComparator] with one that tolerates
/// [tolerance] (a fraction of pixels) of difference. A no-op when another
/// comparator is installed.
void installTolerantGoldenComparator(double tolerance) {
  final previous = goldenFileComparator;
  if (previous is LocalFileComparator) {
    goldenFileComparator = _TolerantGoldenComparator(
      previous.basedir,
      tolerance,
    );
  }
}

class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(Uri baseDir, this.threshold)
    // LocalFileComparator derives basedir from the dirname of the given test
    // file URI; a placeholder filename in baseDir reproduces the original.
    : super(Uri.parse('${baseDir}flutter_test_config.dart'));

  final double threshold;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= threshold) return true;
    throw FlutterError(
      await generateFailureOutput(result, golden, basedir),
    );
  }
}
