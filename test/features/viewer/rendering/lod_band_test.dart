// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/viewer/rendering/lod_band.dart';

void main() {
  group('LodBandRouter.bandFor', () {
    test('overview band below 0.25', () {
      expect(LodBandRouter.bandFor(0.05), LodBand.overview);
      expect(LodBandRouter.bandFor(0.249), LodBand.overview);
    });

    test('mid band in [0.25, 0.75)', () {
      expect(LodBandRouter.bandFor(0.25), LodBand.mid);
      expect(LodBandRouter.bandFor(0.5), LodBand.mid);
      expect(LodBandRouter.bandFor(0.7499), LodBand.mid);
    });

    test('detail band at and above 0.75', () {
      expect(LodBandRouter.bandFor(0.75), LodBand.detail);
      expect(LodBandRouter.bandFor(1), LodBand.detail);
      expect(LodBandRouter.bandFor(10), LodBand.detail);
    });

    test('extreme low zoom still falls into overview', () {
      expect(LodBandRouter.bandFor(0), LodBand.overview);
    });
  });
}
