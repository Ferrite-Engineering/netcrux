// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The Pro analysis surfaces that can dock into the workspace's right
/// analysis dock (the pane that swaps in for the inspector).
///
/// Open-core declares the vocabulary so the docking chrome (the right
/// IDE pane, its visibility logic, and the View-menu toggles) can be
/// built and tested without the Pro overlay; the overlay supplies the
/// actual panel widgets through `analysisPanelBuilderProvider`.
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
}
