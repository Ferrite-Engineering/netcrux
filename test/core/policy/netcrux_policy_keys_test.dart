// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/policy/netcrux_policy_keys.dart';

/// NetCrux's policy namespace and audit vocabulary: the names are declared
/// and well-formed. Whether a key is honoured is tested where its
/// consumer lives (`org_cross_probe_allowlist_test.dart` for the cross-probe
/// allowlist).
void main() {
  group('the namespace is registered and non-empty', () {
    test('the product id matches the schema', () {
      expect(NetCruxPolicyKeys.productId, 'netcrux');
    });

    test('keys and kinds are declared', () {
      expect(NetCruxPolicyKeys.all, isNotEmpty);
      expect(NetCruxAuditKinds.all, isNotEmpty);
    });

    test('no key or kind is blank, and none collide', () {
      for (final k in NetCruxPolicyKeys.all) {
        expect(k.trim(), isNotEmpty);
      }
      for (final k in NetCruxAuditKinds.all) {
        expect(k.trim(), isNotEmpty);
        expect(k, contains('.'), reason: 'kinds are dotted: noun.verb');
      }
    });
  });
}
