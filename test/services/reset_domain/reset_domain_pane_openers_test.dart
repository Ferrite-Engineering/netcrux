// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/reset_domain/reset_domain_pane_openers.dart';

void main() {
  group('Reset Domain pane openers', () {
    testWidgets(
      'default showResetDomainAnalysisPaneOpener is a no-op',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  final opener = ref.watch(
                    showResetDomainAnalysisPaneOpenerProvider,
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
      'default clearResetAnalysisSelectionOpener is a no-op',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  final opener = ref.watch(
                    clearResetAnalysisSelectionOpenerProvider,
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
              showResetDomainAnalysisPaneOpenerProvider.overrideWithValue((_) {
                calls++;
              }),
            ],
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  final opener = ref.watch(
                    showResetDomainAnalysisPaneOpenerProvider,
                  );
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
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(showResetDomainAnalysisPaneOpenerProvider),
        isA<ShowResetDomainAnalysisPaneOpener>(),
      );
      expect(
        container.read(runResetDomainAnalysisOpenerProvider),
        isA<RunResetDomainAnalysisOpener>(),
      );
      expect(
        container.read(showResetCrossingForSelectedSignalOpenerProvider),
        isA<ShowResetCrossingForSelectedSignalOpener>(),
      );
      expect(
        container.read(clearResetAnalysisSelectionOpenerProvider),
        isA<ClearResetAnalysisSelectionOpener>(),
      );
    });
  });
}
