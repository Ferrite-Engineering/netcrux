// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The surfaces that can dock into the workspace's right dock, beside the
/// inspector.
///
/// Open-core declares the vocabulary so the docking chrome (the right
/// IDE pane, its visibility logic, and the View-menu toggles) can be
/// built and tested without the Pro overlay. Open core builds the
/// [bookmarks] and [annotations] panels itself; the overlay supplies the
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

  /// The design's bookmarks: named places to return to. Docked beside the
  /// schematic so a row click lands on the element while the list stays in
  /// view.
  bookmarks,

  /// The design's annotations: Markdown notes on schematic elements. Docked
  /// beside the schematic, where the badge on an annotated cell opens it at
  /// that cell's note.
  annotations,
}
