// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/waveform_format.dart';
import 'package:netcrux/domain/models/activity/waveform_source.dart';

void main() {
  group('WaveformSource', () {
    final ts = DateTime.utc(2026, 5, 25, 14, 30);

    WaveformSource fresh() => WaveformSource(
      filePath: '/tmp/dump.vcd',
      format: WaveformFormat.vcd,
      loadedAt: ts,
      fingerprint: 'abc123',
      fileSizeBytes: 1024,
    );

    test('JSON round-trip preserves all fields', () {
      final source = fresh();
      final json = source.toJson();
      final restored = WaveformSource.fromJson(json);
      expect(restored, source);
    });

    test('fromJson handles missing fields by using safe defaults', () {
      final restored = WaveformSource.fromJson(const <String, Object?>{});
      expect(restored.filePath, '');
      expect(restored.format, WaveformFormat.vcd);
      expect(restored.fingerprint, '');
      expect(restored.fileSizeBytes, 0);
      expect(restored.loadedAt.isUtc, true);
      expect(restored.loadedAt.millisecondsSinceEpoch, 0);
    });

    test('equality and hash are value-based', () {
      expect(fresh(), fresh());
      expect(fresh().hashCode, fresh().hashCode);
      expect(
        fresh(),
        isNot(fresh().copyWith(filePath: '/other/path.vcd')),
      );
      expect(
        fresh(),
        isNot(fresh().copyWith(format: WaveformFormat.fst)),
      );
      expect(
        fresh(),
        isNot(fresh().copyWith(fingerprint: 'def')),
      );
    });

    test('copyWith replaces individual fields', () {
      final base = fresh();
      final replaced = base.copyWith(fingerprint: 'xyz');
      expect(replaced.fingerprint, 'xyz');
      expect(replaced.filePath, base.filePath);
      expect(replaced.format, base.format);
      expect(replaced.loadedAt, base.loadedAt);
      expect(replaced.fileSizeBytes, base.fileSizeBytes);
    });

    test('toString includes file, format, fingerprint, size', () {
      final s = fresh().toString();
      expect(s, contains('/tmp/dump.vcd'));
      expect(s, contains('vcd'));
      expect(s, contains('abc123'));
      expect(s, contains('1024'));
    });
  });
}
