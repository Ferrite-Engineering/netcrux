// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/waveform_format.dart';
import 'package:netcrux/domain/models/activity/waveform_source.dart';
import 'package:netcrux/domain/models/activity/waveform_source_event.dart';

void main() {
  final loadedAt = DateTime.utc(2026, 5, 25, 14, 30);

  WaveformSource source({String path = '/tmp/dump.vcd'}) => WaveformSource(
    filePath: path,
    format: WaveformFormat.vcd,
    loadedAt: loadedAt,
    fingerprint: 'abc123',
    fileSizeBytes: 1024,
  );

  group('WaveformSourceLoadedEvent', () {
    test('equal sources compare equal and share a hash', () {
      final a = WaveformSourceLoadedEvent(source: source());
      final b = WaveformSourceLoadedEvent(source: source());
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, a);
    });

    test('different sources compare unequal', () {
      final a = WaveformSourceLoadedEvent(source: source());
      final b = WaveformSourceLoadedEvent(
        source: source(path: '/tmp/other.vcd'),
      );
      expect(a, isNot(b));
    });

    test('toString names the source', () {
      expect(
        WaveformSourceLoadedEvent(source: source()).toString(),
        contains('/tmp/dump.vcd'),
      );
    });
  });

  group('WaveformSourceUnloadedEvent', () {
    test('equality keys on the previous path', () {
      const a = WaveformSourceUnloadedEvent(previousFilePath: '/tmp/a.vcd');
      const b = WaveformSourceUnloadedEvent(previousFilePath: '/tmp/a.vcd');
      const c = WaveformSourceUnloadedEvent(previousFilePath: '/tmp/b.vcd');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('toString names the closed file', () {
      expect(
        const WaveformSourceUnloadedEvent(
          previousFilePath: '/tmp/a.vcd',
        ).toString(),
        contains('/tmp/a.vcd'),
      );
    });
  });

  group('WaveformSourceLoadFailedEvent', () {
    test('equality keys on both path and message', () {
      const a = WaveformSourceLoadFailedEvent(
        filePath: '/tmp/a.vcd',
        message: 'unreadable',
      );
      const sameFields = WaveformSourceLoadFailedEvent(
        filePath: '/tmp/a.vcd',
        message: 'unreadable',
      );
      const otherMessage = WaveformSourceLoadFailedEvent(
        filePath: '/tmp/a.vcd',
        message: 'truncated',
      );
      const otherPath = WaveformSourceLoadFailedEvent(
        filePath: '/tmp/b.vcd',
        message: 'unreadable',
      );
      expect(a, sameFields);
      expect(a.hashCode, sameFields.hashCode);
      expect(a, isNot(otherMessage));
      expect(a, isNot(otherPath));
    });

    test('toString carries the path and the message', () {
      const event = WaveformSourceLoadFailedEvent(
        filePath: '/tmp/a.vcd',
        message: 'unreadable',
      );
      expect(event.toString(), contains('/tmp/a.vcd'));
      expect(event.toString(), contains('unreadable'));
    });
  });

  test('variants of different runtime types never compare equal', () {
    final loaded = WaveformSourceLoadedEvent(source: source());
    const unloaded = WaveformSourceUnloadedEvent(
      previousFilePath: '/tmp/dump.vcd',
    );
    const failed = WaveformSourceLoadFailedEvent(
      filePath: '/tmp/dump.vcd',
      message: 'unreadable',
    );
    expect(loaded, isNot(unloaded));
    expect(unloaded, isNot(failed));
    expect(failed, isNot(loaded));
  });
}
