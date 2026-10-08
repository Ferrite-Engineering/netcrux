// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The closed vocabulary for the telemetry event whose call sites live in the
/// Pro overlay.
///
/// It is declared **here**, in open core, for the same reason
/// `kNetcruxEventCatalog` is: the catalog and the conformance test that checks
/// it against the ingestion Worker's grammar cannot see the overlay's source,
/// so a vocabulary defined over there could drift from the pinned list without
/// anything failing. Declaring the enum in the repository that owns the catalog
/// makes the Pro call sites and the catalog two views of one declaration, and
/// the conformance test asserts they agree.
///
/// It is an `Enum` rather than `String` constants because the values reach the
/// wire through `telemetryEnumToken`, whose whole point is that its parameter
/// type keeps the closed set in the type system instead of in reviewer
/// attention (event properties are a closed vocabulary —
/// `https://edacrux.app/telemetry`).
///
/// A second vocabulary belongs to this set and is not here:
/// `NetcruxGatedFeature` (`tier.gate_hit {feature}`) lives in
/// `core/license/netcrux_gated_feature.dart`, because its mapping has to sit
/// beside `NetcruxActionRequiredTier` in `core/` and the layer matrix
/// (`docs/ARCHITECTURE.md` §6.2)
/// forbids `core/` from importing `services/`. That file explains the trade.
library;

/// Which Pro analysis a user ran (`analysis.run {kind}`).
///
/// The roadmap question is which Pro analyses drive conversion, so the
/// constants are the six user-visible analyses, not the services that
/// implement them.
enum NetcruxAnalysisKind {
  /// Transitive cone-of-influence trace — the Pro counterpart of open core's
  /// single-step `trace.used`.
  coi,

  /// X-propagation causal-chain walk.
  xTrace,

  /// Finite-state-machine detection across the design.
  fsm,

  /// Clock-domain-crossing analysis.
  cdc,

  /// Reset-domain analysis.
  reset,

  /// Net-activity heat-map analysis over a loaded waveform.
  activity,
}
