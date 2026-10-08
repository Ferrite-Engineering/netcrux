// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The closed vocabulary of tier-gated features, and the reason it lives in
/// `core/license/` rather than beside the other telemetry vocabularies in
/// `services/telemetry/netcrux_telemetry_vocabulary.dart`.
///
/// `NetcruxAction` is a `core/` type, and the layer matrix
/// (`docs/ARCHITECTURE.md` §6.2) lets `core/`
/// import only `core` and `l10n`. The one property this vocabulary has to hold
/// above all others is that its mapping from actions sits next to
/// `NetcruxActionRequiredTier`, so a new Pro action cannot gain a tier without
/// gaining a feature id in the same switch statement. That adjacency is only
/// available inside `core/`, and gating is a licensing concept, so it lands
/// next to the upgrade-dialog and badge string adapters rather than being
/// bent into `services/`.
library;

/// Which tier-gated feature a user reached for and was denied
/// (`tier.gate_hit {feature}`, one of the commercial-group events).
///
/// **This is not the dialog's `featureName`.** `NetcruxUpgradeDialog` takes a
/// *localized display label* — "Show Cone of Influence (Fanin)" in English and
/// something else in each of the other four locales. Sending that would put a
/// per-locale free-form string on the wire, which the ingestion Worker's
/// `[a-z0-9_]{1,64}` value class rejects outright: the property would be
/// dropped and the event kept, leaving a healthy-looking counter with a
/// permanently empty dimension. Denial sites therefore pass one of these
/// constants alongside the label, and the two travel together but never mix.
///
/// **Granularity is the priced feature, not the menu item.** Fanin and fanout
/// are one purchase decision, and so are the three CDC entry points; a user who
/// hits the gate from any of them wanted the same thing. The tokens deliberately
/// coincide with `NetcruxAnalysisKind` where the same feature appears in both
/// vocabularies, so
/// `tier.gate_hit {feature: cdc}` and `analysis.run {kind: cdc}` join directly —
/// wanted-but-locked over used-when-owned, per feature, is the whole point of
/// the commercial group.
///
/// A value is added here only when a gate denial can actually reach it; a token
/// nothing emits renders on a dashboard as a real zero.
enum NetcruxGatedFeature {
  /// Multi-step cone of influence — fanin and fanout, from the action
  /// dispatcher or the schematic context menu.
  coi,

  /// X-propagation causal-chain walk.
  xTrace,

  /// Read-only RTL source pane, including "show source for this element".
  sourcePane,

  /// Netlist diff — the pane, the comparison load, and diff navigation.
  diff,

  /// Custom cell symbols — the manager, SVG import, and per-instance
  /// edit / remove.
  symbol,

  /// FSM detection and the bubble diagram.
  fsm,

  /// Clock-domain-crossing analysis.
  cdc,

  /// Reset-domain analysis.
  reset,

  /// The waveform source behind the switching-activity heatmap.
  waveform,

  /// Switching-activity heatmap and its colour scheme.
  activity,

  /// Originating a cross-probe toward a connected peer.
  crossProbe,

  /// Hosting a collaborative schematic session (Share Session) — Enterprise,
  /// and the only value here whose required tier is not `pro`. Joining is free
  /// in every edition and can never be denied, so this means "tried to host"
  /// and nothing else.
  collaboration,
}
