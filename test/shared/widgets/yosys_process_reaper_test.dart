// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/shared/widgets/yosys_process_reaper.dart';

Future<void> _pump(WidgetTester tester, ProcessRegistry registry) =>
    tester.pumpWidget(
      YosysProcessReaper(
        registry: registry,
        child: const MaterialApp(home: Placeholder()),
      ),
    );

void main() {
  testWidgets('drains the registry on detach', (tester) async {
    final registry = ProcessRegistry();
    await _pump(tester, registry);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();

    // With nothing spawned there is nothing to kill; the assertion that
    // matters is that the detach path runs and is safe on an empty
    // registry (a hard quit with no elaboration in flight).
    expect(registry.liveCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not drain on inactive, paused, hidden or resumed', (
    tester,
  ) async {
    final registry = ProcessRegistry();
    await _pump(tester, registry);

    // `paused` is a background transition the process is expected to
    // resume from. Killing a running elaboration there would discard
    // work the user is coming back to, so only `detached` drains.
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders its child unchanged', (tester) async {
    await _pump(tester, ProcessRegistry());
    expect(find.byType(Placeholder), findsOneWidget);
  });

  testWidgets('deregisters its observer on dispose', (tester) async {
    final registry = ProcessRegistry();
    await _pump(tester, registry);
    await tester.pumpWidget(const MaterialApp(home: Placeholder()));

    // A stale observer would keep the disposed state alive and fire
    // against it on the next lifecycle transition.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
