// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/policy/netcrux_policy_keys.dart';

/// Which products this seat may cross-probe to, per the organization.
///
/// `products.netcrux.crossProbePeerAllowlist` was registered, documented on
/// `administration.html`, and read by nothing: an administrator could list two
/// products, restart every seat, and NetCrux would still offer every peer it
/// discovered. This is the read that makes the key mean something.
///
/// **Matched on product name**, not `peerId` or host. A peer id is per-process
/// and a host is per-machine; neither is a thing an administrator can write
/// down in advance. `"wavecrux"` is.
///
/// **A filter, not an access control.** The product name is the one the peer
/// claims in its own manifest, and any process that can write the user's CXP
/// manifest directory can claim any name. The manifest path does not help:
/// every peer writes `<peer_id>.json` into the same directory, and the peer
/// chooses its own id. A process with that much access can read the design
/// directly, so the key narrows which tools a seat cross-probes to and is
/// documented that way in `docs-site/docs/administration.md`.
///
/// **Absent means no restriction**, which is every seat without a policy file.
/// An administrator who wants cross-probing off entirely writes an empty list —
/// that is a restriction to everything, and is honoured as one.
///
/// Locked and unlocked are the same here, deliberately. This is a restriction,
/// not a default: there is no "the engineer's own allowlist" for it to sit
/// above or below, so an unlocked value is still the only answer available.
final orgCrossProbeAllowlistProvider = Provider<Set<String>?>((ref) {
  final raw =
      ref.watch(cruxPolicyProvider).document.products[NetCruxPolicyKeys
          .productId]?[NetCruxPolicyKeys.crossProbePeerAllowlist];
  return parseCrossProbeAllowlist(raw);
}, name: 'orgCrossProbeAllowlistProvider');

/// Parses the key's value: a list of product names, or the `{value, locked}`
/// wrapper around one.
///
/// Returns `null` for "the organization said nothing", which is different from
/// an empty set — that means "nothing is allowed" and is a real answer.
Set<String>? parseCrossProbeAllowlist(Object? raw) {
  var value = raw;
  if (value is Map<String, Object?> && value.containsKey('value')) {
    value = value['value'];
  }
  if (value is! List) return null;
  return <String>{
    for (final entry in value)
      if (entry is String && entry.trim().isNotEmpty)
        entry.trim().toLowerCase(),
  };
}

/// Whether [productName] may be cross-probed to under [allowlist].
///
/// Fails **closed** on a malformed entry only in the sense that a list which
/// parses to nothing is an empty allowlist, not an absent one. A key an
/// administrator wrote is always treated as an intent to restrict.
bool crossProbeAllowed(Set<String>? allowlist, String productName) =>
    allowlist == null || allowlist.contains(productName.trim().toLowerCase());
