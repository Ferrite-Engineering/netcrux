// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/collaboration/collaboration_session_openers.dart';

void main() {
  testWidgets('the open-core openers are no-ops', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox.shrink();
        },
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(shareSessionOpenerProvider)(context);
    container.read(joinSessionOpenerProvider)(context);

    expect(tester.takeException(), isNull);
  });

  test('the overlay can replace each opener', () {
    var shared = 0;
    var joined = 0;
    final container = ProviderContainer(
      overrides: [
        shareSessionOpenerProvider.overrideWithValue((_) => shared++),
        joinSessionOpenerProvider.overrideWithValue((_) => joined++),
      ],
    );
    addTearDown(container.dispose);

    final context = _FakeContext();
    container.read(shareSessionOpenerProvider)(context);
    container.read(joinSessionOpenerProvider)(context);

    expect((shared, joined), (1, 1));
  });
}

class _FakeContext extends Fake implements BuildContext {}
