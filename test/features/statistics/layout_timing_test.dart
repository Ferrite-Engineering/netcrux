// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/statistics/providers/layout_timing_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  LayoutTimingNotifier notifier() =>
      container.read(layoutTimingProvider.notifier);
  LayoutTimingStats stats() => container.read(layoutTimingProvider);

  test('starts empty', () {
    expect(stats().hasSample, isFalse);
    expect(stats().recentMillis, isEmpty);
  });

  test('completed records the duration', () {
    notifier().completed(const Duration(milliseconds: 250));

    expect(stats().lastMicroseconds, 250000);
    expect(stats().recentMillis, <double>[250]);
    expect(stats().hasSample, isTrue);
  });

  test('carries no isRunning flag — the graph provider IS the layout '
      'pass, so a mirrored flag could only ever disagree with it', () {
    // Regression pin: an earlier draft set a running flag from inside
    // currentLaidOutGraphProvider's build, which Riverpod rejects
    // ("providers are not allowed to modify other providers during their
    // initialization"). The strip reads isLoading from that provider.
    notifier().completed(const Duration(milliseconds: 5));
    expect(stats().toString(), isNot(contains('running')));
  });

  test('the history window is bounded', () {
    final n = notifier();
    for (var i = 0; i < kLayoutTimingWindow + 15; i++) {
      n.completed(Duration(milliseconds: i + 1));
    }
    expect(stats().recentMillis.length, kLayoutTimingWindow);
    expect(
      stats().recentMillis.last,
      (kLayoutTimingWindow + 15).toDouble(),
      reason: 'the newest sample must survive the trim',
    );
  });

  test('successive passes accumulate in order', () {
    notifier()
      ..completed(const Duration(milliseconds: 10))
      ..completed(const Duration(milliseconds: 20));
    expect(stats().recentMillis, <double>[10, 20]);
  });
}
