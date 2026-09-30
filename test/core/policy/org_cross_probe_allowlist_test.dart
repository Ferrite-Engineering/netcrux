// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `products.netcrux.crossProbePeerAllowlist` was registered, documented, and
// read by nothing: an administrator could list two products, restart every
// seat, and NetCrux still offered every peer it discovered.

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/policy/org_cross_probe_allowlist.dart';

void main() {
  group('parseCrossProbeAllowlist', () {
    test('absent is null — no restriction, which is every default seat', () {
      expect(parseCrossProbeAllowlist(null), isNull);
    });

    test('a non-list is null rather than an empty allowlist', () {
      // "The administrator wrote nonsense" must not silently become "nothing
      // is allowed"; the lint is where a malformed value gets named.
      expect(parseCrossProbeAllowlist('wavecrux'), isNull);
      expect(parseCrossProbeAllowlist(42), isNull);
    });

    test('an EMPTY list is a real answer: nothing is allowed', () {
      // Distinct from absent, and deliberately so — it is how an
      // administrator turns cross-probing off entirely.
      expect(parseCrossProbeAllowlist(<Object?>[]), isEmpty);
      expect(parseCrossProbeAllowlist(<Object?>[]), isNotNull);
    });

    test('names are matched case- and whitespace-insensitively', () {
      final set = parseCrossProbeAllowlist(<Object?>[' WaveCrux ', 'LINTCRUX']);
      expect(set, {'wavecrux', 'lintcrux'});
    });

    test('the locked wrapper is unwrapped like every other key', () {
      final set = parseCrossProbeAllowlist(<String, Object?>{
        'value': <Object?>['wavecrux'],
        'locked': true,
      });
      expect(set, {'wavecrux'});
    });
  });

  group('crossProbeAllowed', () {
    test('no allowlist allows everything', () {
      expect(crossProbeAllowed(null, 'wavecrux'), isTrue);
      expect(crossProbeAllowed(null, 'anything'), isTrue);
    });

    test('an empty allowlist allows nothing', () {
      expect(crossProbeAllowed(<String>{}, 'wavecrux'), isFalse);
    });

    test('only the named products pass', () {
      const list = {'wavecrux'};
      expect(crossProbeAllowed(list, 'WaveCrux'), isTrue);
      expect(crossProbeAllowed(list, 'simcrux'), isFalse);
    });
  });
}
