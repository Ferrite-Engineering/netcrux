// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/fsm/fsm_pane_openers.dart';

void main() {
  group('FSM pane openers', () {
    testWidgets('show FSM bubble diagram defaults to a no-op', (tester) async {
      late BuildContext capturedContext;
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              capturedContext = context;
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final showOpener = capturedRef.read(showFsmBubbleDiagramOpenerProvider);
      final clearOpener = capturedRef.read(clearFsmSelectionOpenerProvider);
      final detectOpener = capturedRef.read(
        detectFsmForCurrentRegisterOpenerProvider,
      );
      final runOpener = capturedRef.read(
        runFsmDetectionAcrossDesignOpenerProvider,
      );
      // None of these throws — they are all open-core no-ops.
      showOpener(capturedContext);
      clearOpener(capturedContext);
      detectOpener(capturedContext, capturedRef);
      runOpener(capturedContext, capturedRef);
      expect(tester.takeException(), isNull);
    });

    testWidgets('overrideWithValue replaces an opener', (tester) async {
      var showCalls = 0;
      late BuildContext capturedContext;
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            showFsmBubbleDiagramOpenerProvider.overrideWithValue(
              (_) => showCalls++,
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedContext = context;
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      capturedRef.read(showFsmBubbleDiagramOpenerProvider)(capturedContext);
      expect(showCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
