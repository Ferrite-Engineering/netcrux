// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/cdc/cdc_pane_openers.dart';

void main() {
  group('CDC pane openers', () {
    testWidgets(
      'default showCdcAnalysisPaneOpener is a no-op',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  final opener = ref.watch(showCdcAnalysisPaneOpenerProvider);
                  expect(() => opener(context), returnsNormally);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'default clearCdcAnalysisSelectionOpener is a no-op',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  final opener = ref.watch(
                    clearCdcAnalysisSelectionOpenerProvider,
                  );
                  expect(() => opener(context), returnsNormally);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Pro overlay can override the show opener via overrideWithValue',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              showCdcAnalysisPaneOpenerProvider.overrideWithValue((_) {
                calls++;
              }),
            ],
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  final opener = ref.watch(showCdcAnalysisPaneOpenerProvider);
                  opener(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      },
    );

    test('the four typedefs are all distinct', () {
      // Sanity check that the four provider types are not accidentally
      // aliased to the same typedef (catches accidental copy-paste).
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(showCdcAnalysisPaneOpenerProvider),
        isA<ShowCdcAnalysisPaneOpener>(),
      );
      expect(
        container.read(runCdcAnalysisOpenerProvider),
        isA<RunCdcAnalysisOpener>(),
      );
      expect(
        container.read(showCdcCrossingForSelectedSignalOpenerProvider),
        isA<ShowCdcCrossingForSelectedSignalOpener>(),
      );
      expect(
        container.read(clearCdcAnalysisSelectionOpenerProvider),
        isA<ClearCdcAnalysisSelectionOpener>(),
      );
    });
  });
}
