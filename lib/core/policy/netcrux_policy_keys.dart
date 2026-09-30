// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// NetCrux's namespace in `.crux-policy.json`, and its audit event kinds.
///
/// **These declare the keys; each key is honoured where its feature lives.**
/// `crossProbePeerAllowlist` is read by `orgCrossProbeAllowlistProvider`
/// (`core/policy/org_cross_probe_allowlist.dart`); `symbolLibraries` is read
/// by the Pro overlay's organization symbol libraries. Both consumers read the
/// raw value from `cruxPolicyProvider` and state their own precedence, rather
/// than going through the shared `PolicyResolver`: both keys are list-valued,
/// and the resolver reads any map as its `{value, locked}` wrapper.
///
/// The published key reference is
/// `https://edacrux.app/policy-reference#product-keys`. Register against
/// **its** names: it is the one list the four products share, so an
/// administrator's file means the same thing in every product.
abstract final class NetCruxPolicyKeys {
  /// The product id this namespace lives under.
  static const String productId = 'netcrux';

  /// `products.netcrux.crossProbePeerAllowlist` — which CXP peers may be cross-probed to.
  static const String crossProbePeerAllowlist = 'crossProbePeerAllowlist';

  /// `products.netcrux.symbolLibraries` — org-wide custom-symbol packs.
  ///
  /// A list of directories on the organization's own share, each holding the
  /// same `.json` (+ sibling `.svg`) files the per-user and per-project stores
  /// hold. **Nothing is hosted**: a share is a path the customer already has.
  ///
  /// Unlocked, an org pack is a *policy default* and sits BELOW the engineer's
  /// own per-user and per-project symbols — both of which are "the user
  /// setting" in the policy precedence order
  /// (`https://edacrux.app/policy-reference#precedence`). **Locked**, it
  /// outranks both: that is the
  /// mandatory-pack case, for an organization standardising on a corporate
  /// style.
  static const String symbolLibraries = 'symbolLibraries';

  /// Every key this product registers, for the conformance test.
  static const Set<String> all = <String>{
    crossProbePeerAllowlist,
    symbolLibraries,
  };
}

/// The audit events NetCrux records.
///
/// **Kinds are per-product on purpose.** The envelope is shared; a shared enum
/// of kinds would need editing in `crux-shared` every time any one of four
/// products learned a new event.
abstract final class NetCruxAuditKinds {
  /// `schematic.opened`
  static const String schematicOpened = 'schematic.opened';

  /// `session.saved`
  static const String sessionSaved = 'session.saved';

  /// `crossprobe.originated`
  static const String crossprobeOriginated = 'crossprobe.originated';

  /// `search.executed`
  static const String searchExecuted = 'search.executed';

  /// Every kind this product registers, for the conformance test.
  static const Set<String> all = <String>{
    schematicOpened,
    sessionSaved,
    crossprobeOriginated,
    searchExecuted,
  };
}
