// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/collaboration/collab_follow_detached_provider.dart';

void main() {
  test('detaching is local and reversible', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(collabFollowDetachedProvider.notifier);

    expect(container.read(collabFollowDetachedProvider), isFalse);
    notifier.detach();
    expect(container.read(collabFollowDetachedProvider), isTrue);
    notifier.resume();
    expect(container.read(collabFollowDetachedProvider), isFalse);
  });

  testWidgets('an idle follower is snapped back, and navigating keeps them '
      'away', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(collabFollowDetachedProvider.notifier)
      ..detach();

    await tester.pump(const Duration(seconds: 8));
    // Still navigating: the window restarts.
    notifier.detach();
    await tester.pump(const Duration(seconds: 8));
    expect(container.read(collabFollowDetachedProvider), isTrue);

    await tester.pump(kCollabFollowIdleResume);
    expect(container.read(collabFollowDetachedProvider), isFalse);
  });

  testWidgets('a null window resumes only when asked', (tester) async {
    final container = ProviderContainer(
      overrides: [collabFollowIdleResumeProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);
    container.read(collabFollowDetachedProvider.notifier).detach();
    await tester.pump(const Duration(minutes: 5));
    expect(container.read(collabFollowDetachedProvider), isTrue);
  });
}
