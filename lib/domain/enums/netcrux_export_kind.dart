// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The three schematic export formats NetCrux writes.
///
/// Promoted out of the workspace action dispatcher's private `_ExportFormat`
/// when `export.completed {kind}` landed: the dispatcher chooses the format and
/// [`SchematicExportController`] reports the completed one, so the two need a
/// shared declaration. Being a closed enum is also what lets the value reach
/// telemetry through `telemetryEnumToken` rather than as a string derived from
/// the file the user picked.
enum NetcruxExportKind {
  /// Raster capture of the canvas via `RenderRepaintBoundary.toImage`.
  png,

  /// Vector rendering of the laid-out graph via `SvgExporter`.
  svg,

  /// The active scope's slice of the Yosys netlist document.
  json,
}
