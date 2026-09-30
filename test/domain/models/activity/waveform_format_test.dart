// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/waveform_format.dart';

void main() {
  group('WaveformFormat', () {
    test('JSON round-trip preserves each variant', () {
      for (final f in WaveformFormat.values) {
        expect(WaveformFormat.fromJsonString(f.toJsonString()), f);
      }
    });

    test('unknown JSON tag falls back to vcd', () {
      expect(
        WaveformFormat.fromJsonString('not-a-real-format'),
        WaveformFormat.vcd,
      );
    });

    test('fromPath detects .vcd / .fst / .ghw + falls back to vcd', () {
      expect(
        WaveformFormat.fromPath('/tmp/dump.vcd'),
        WaveformFormat.vcd,
      );
      expect(
        WaveformFormat.fromPath('/tmp/dump.fst'),
        WaveformFormat.fst,
      );
      expect(
        WaveformFormat.fromPath('/tmp/dump.ghw'),
        WaveformFormat.ghw,
      );
      // Case-insensitivity.
      expect(
        WaveformFormat.fromPath('/tmp/DUMP.FST'),
        WaveformFormat.fst,
      );
      // Unknown extension → vcd.
      expect(
        WaveformFormat.fromPath('/tmp/dump.txt'),
        WaveformFormat.vcd,
      );
    });
  });
}
