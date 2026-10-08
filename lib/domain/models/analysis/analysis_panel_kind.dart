// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The surfaces that can dock into the workspace's right dock, beside the
/// inspector.
///
/// Open-core declares the vocabulary so the docking chrome (the right
/// IDE pane, its visibility logic, and the View-menu toggles) can be
/// built and tested without the Pro overlay. Open core builds the
/// [annotations] panel itself; the overlay supplies the
/// widgets for the analyses through `analysisPanelBuilderProvider`.
enum AnalysisPanelKind {
  /// Clock-domain-crossing analysis (Pro).
  cdc,

  /// Reset-domain analysis (Pro).
  resetDomain,

  /// FSM extraction / bubble diagram (Pro).
  fsm,

  /// Full-design FSM detection RESULTS LIST — the "Detected N FSMs"
  /// list, docked like the other analysis surfaces rather than shown as a
  /// centered modal (Pro).
  fsmResults,

  /// Switching-activity heatmap (Pro).
  activity,

  /// Netlist diff (Pro).
  diff,

  /// RTL source view: the file behind the selected element, with its line
  /// highlighted. Docked beside the schematic rather than shown as a modal,
  /// so both directions of the source link stay in view (Pro).
  source,

  /// The design's annotations: titled Markdown notes on schematic elements.
  /// Docked beside the schematic so a row click lands on the element while
  /// the list stays in view, and the badge on an annotated cell opens it at
  /// that cell's note.
  annotations,
}

/// Which analysis panels are Pro.
extension AnalysisPanelKindTier on AnalysisPanelKind {
  /// Whether this panel is a NetCrux Pro surface. Annotations are open core;
  /// every analysis and the source view are Pro.
  ///
  /// A collaborative session uses it to decide what a follower is shown when
  /// the presenter has a panel open: an open-core panel opens for everyone, a
  /// Pro one only where this build and licence include Pro, and otherwise the
  /// follower is told it requires NetCrux Pro rather than given it.
  bool get requiresPro => switch (this) {
    AnalysisPanelKind.annotations => false,
    AnalysisPanelKind.cdc ||
    AnalysisPanelKind.resetDomain ||
    AnalysisPanelKind.fsm ||
    AnalysisPanelKind.fsmResults ||
    AnalysisPanelKind.activity ||
    AnalysisPanelKind.diff ||
    AnalysisPanelKind.source => true,
  };
}

/// The panel named [name], or `null` when no panel has that name — a peer on
/// a later build may name one this build does not have.
AnalysisPanelKind? analysisPanelKindNamed(String? name) {
  if (name == null) return null;
  for (final kind in AnalysisPanelKind.values) {
    if (kind.name == name) return kind;
  }
  return null;
}
