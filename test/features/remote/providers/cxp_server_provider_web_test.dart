// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';

/// Runs in a real browser (`flutter test --platform chrome`), where
/// resolving the suite-shared CXP discovery directory throws: the default
/// wiring must never reach it.
void main() {
  test('the browser build starts no CXP server and resolves no discovery '
      'directory', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(cxpTransportAvailableProvider), isFalse);
    expect(await container.read(cxpServerHostProvider.future), isNull);
    expect(container.exists(cxpManifestDirectoryProvider), isFalse);
  });
}
