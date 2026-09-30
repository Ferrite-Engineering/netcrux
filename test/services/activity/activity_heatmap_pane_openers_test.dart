// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/activity/activity_heatmap_pane_openers.dart';

void main() {
  group('activity heatmap pane openers', () {
    test('default openers resolve to non-null typedef instances', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(showActivityHeatmapOpenerProvider),
        isA<ShowActivityHeatmapOpener>(),
      );
      expect(
        container.read(openWaveformFileOpenerProvider),
        isA<OpenWaveformFileOpener>(),
      );
      expect(
        container.read(closeWaveformFileOpenerProvider),
        isA<CloseWaveformFileOpener>(),
      );
      expect(
        container.read(runActivityAnalysisOpenerProvider),
        isA<RunActivityAnalysisOpener>(),
      );
      expect(
        container.read(clearActivityColoringOpenerProvider),
        isA<ClearActivityColoringOpener>(),
      );
      expect(
        container.read(configureActivitySchemeOpenerProvider),
        isA<ConfigureActivitySchemeOpener>(),
      );
    });

    testWidgets('Pro overlay can override each opener', (tester) async {
      var shows = 0;
      var opens = 0;
      var closes = 0;
      var runs = 0;
      var clears = 0;
      var schemes = 0;

      late BuildContext capturedContext;
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            showActivityHeatmapOpenerProvider.overrideWithValue((_) => shows++),
            openWaveformFileOpenerProvider.overrideWithValue((_, _) => opens++),
            closeWaveformFileOpenerProvider.overrideWithValue(
              (_, _) => closes++,
            ),
            runActivityAnalysisOpenerProvider.overrideWithValue(
              (_, _) => runs++,
            ),
            clearActivityColoringOpenerProvider.overrideWithValue(
              (_, _) => clears++,
            ),
            configureActivitySchemeOpenerProvider.overrideWithValue(
              (_) => schemes++,
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedContext = context;
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      capturedRef.read(showActivityHeatmapOpenerProvider)(capturedContext);
      capturedRef.read(openWaveformFileOpenerProvider)(
        capturedContext,
        capturedRef,
      );
      capturedRef.read(closeWaveformFileOpenerProvider)(
        capturedContext,
        capturedRef,
      );
      capturedRef.read(runActivityAnalysisOpenerProvider)(
        capturedContext,
        capturedRef,
      );
      capturedRef.read(clearActivityColoringOpenerProvider)(
        capturedContext,
        capturedRef,
      );
      capturedRef.read(configureActivitySchemeOpenerProvider)(
        capturedContext,
      );

      expect(shows, 1);
      expect(opens, 1);
      expect(closes, 1);
      expect(runs, 1);
      expect(clears, 1);
      expect(schemes, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
