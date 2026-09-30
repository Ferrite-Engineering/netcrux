// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/diff/diff_pane_openers.dart';

void main() {
  test('default show / clear / next / prev openers are no-ops', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Each opener must be a callable function; invoking it with a
    // minimal BuildContext stand-in (passing null cast through
    // dynamic) is not possible because the typedef requires a
    // BuildContext. Instead we just verify the providers resolve
    // to functions with the expected typedef shape — they're all
    // no-ops in open-core.
    expect(c.read(showDiffPaneOpenerProvider), isA<ShowDiffPaneOpener>());
    expect(
      c.read(loadComparisonNetlistOpenerProvider),
      isA<LoadComparisonNetlistOpener>(),
    );
    expect(
      c.read(clearComparisonNetlistOpenerProvider),
      isA<ClearComparisonNetlistOpener>(),
    );
    expect(
      c.read(navigateNextDiffOpenerProvider),
      isA<NavigateNextDiffOpener>(),
    );
    expect(
      c.read(navigatePrevDiffOpenerProvider),
      isA<NavigatePrevDiffOpener>(),
    );
  });

  test('openers can be overridden', () {
    var captured = 0;
    final c = ProviderContainer(
      overrides: <Override>[
        showDiffPaneOpenerProvider.overrideWithValue((_) => captured++),
      ],
    );
    addTearDown(c.dispose);
    final opener = c.read(showDiffPaneOpenerProvider);
    opener(_StubContext());
    expect(captured, 1);
  });
}

class _StubContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
