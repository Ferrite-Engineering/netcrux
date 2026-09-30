// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/waveform_source_service.dart';

void main() {
  group('NoopWaveformSourceService', () {
    test('loadWaveform throws UnimplementedWaveformLoad', () async {
      const service = NoopWaveformSourceService();
      await expectLater(
        service.loadWaveform('/tmp/missing.vcd'),
        throwsA(isA<UnimplementedWaveformLoad>()),
      );
    });

    test('UnimplementedWaveformLoad carries the requested path', () async {
      const service = NoopWaveformSourceService();
      try {
        await service.loadWaveform('/tmp/some.vcd');
        fail('expected throw');
      } on UnimplementedWaveformLoad catch (e) {
        expect(e.filePath, '/tmp/some.vcd');
        expect(e.message, contains('Pro overlay'));
        expect(e.toString(), contains('/tmp/some.vcd'));
      }
    });

    test('unloadWaveform is a safe no-op', () async {
      const service = NoopWaveformSourceService();
      await service.unloadWaveform(); // no throw
    });

    test('queryNetTransitions returns empty', () async {
      const service = NoopWaveformSourceService();
      final transitions = await service.queryNetTransitions('top.q');
      expect(transitions, isEmpty);
    });

    test('queryNetTransitions with bounded range returns empty', () async {
      const service = NoopWaveformSourceService();
      final transitions = await service.queryNetTransitions(
        'top.q',
        startNs: 0,
        endNs: 100,
      );
      expect(transitions, isEmpty);
    });

    test('loadedNetPaths is empty', () {
      const service = NoopWaveformSourceService();
      expect(service.loadedNetPaths, isEmpty);
    });

    test('sourceEndNs is 0', () {
      const service = NoopWaveformSourceService();
      expect(service.sourceEndNs, 0);
    });

    test('currentSource is null', () {
      const service = NoopWaveformSourceService();
      expect(service.currentSource, isNull);
    });

    test('events stream emits nothing', () async {
      const service = NoopWaveformSourceService();
      var count = 0;
      final sub = service.events.listen((_) => count++);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await sub.cancel();
      expect(count, 0);
    });
  });
}
