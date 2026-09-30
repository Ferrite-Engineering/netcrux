// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/plugins/extra_localizations_delegates_provider.dart';

class _StubDelegate extends LocalizationsDelegate<Object> {
  const _StubDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<Object> load(Locale locale) async => const Object();

  @override
  bool shouldReload(covariant LocalizationsDelegate<Object> old) => false;
}

void main() {
  group('extraLocalizationsDelegatesProvider', () {
    test('returns an empty list by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(extraLocalizationsDelegatesProvider), isEmpty);
    });

    test('honors overrides supplied by the Pro overlay', () {
      const stub = _StubDelegate();
      final container = ProviderContainer(
        overrides: [
          extraLocalizationsDelegatesProvider.overrideWithValue(
            const <LocalizationsDelegate<Object?>>[stub],
          ),
        ],
      );
      addTearDown(container.dispose);

      final delegates = container.read(extraLocalizationsDelegatesProvider);
      expect(delegates, hasLength(1));
      expect(delegates.single, same(stub));
    });
  });
}
