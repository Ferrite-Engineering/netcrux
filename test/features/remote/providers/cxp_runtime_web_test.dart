// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';

/// Runs in a real browser (`flutter test --platform chrome`), where
/// resolving the suite-shared CXP discovery directory throws: the default
/// wiring must never reach it.
void main() {
  test('the browser build starts no CXP runtime and resolves no discovery '
      'directory', () async {
    final container = ProviderContainer(
      overrides: [
        cruxCxpProductBindingProvider.overrideWithValue(kNetcruxCxpBinding),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(cruxCxpTransportAvailableProvider), isFalse);
    expect(await container.read(cruxCxpRuntimeProvider.future), isNull);
    expect(container.exists(cruxCxpManifestDirectoryProvider), isFalse);
  });
}
