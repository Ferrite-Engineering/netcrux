// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/features/annotations/widgets/annotations_panel.dart';

/// Whether open core itself supplies the dock panel for [kind], rather than
/// the builder behind `analysisPanelBuilderProvider`.
bool isOpenCoreAnalysisPanel(AnalysisPanelKind kind) =>
    kind == AnalysisPanelKind.annotations;

/// Builds the dock panel for an [AnalysisPanelKind] open core supplies: the
/// Annotations list.
///
/// The widget mounts inside the active tab's provider scope (the right slot
/// of the per-tab `NetcruxIdeLayout`), so it lists that tab's entries. It
/// lays out at the dock's own width: a row's title and element ellipsize and
/// its menu button stays at the pane's right edge, and an annotation's
/// Markdown wraps to the pane.
///
/// Any other kind is a programming error: it belongs to the overlay's
/// builder, and `isOpenCoreAnalysisPanel` says which are which.
Widget buildOpenCoreAnalysisPanel(
  BuildContext context,
  AnalysisPanelKind kind,
) {
  return switch (kind) {
    AnalysisPanelKind.annotations => const AnnotationsPanel(),
    _ => throw ArgumentError.value(
      kind,
      'kind',
      'is not an open-core analysis panel',
    ),
  };
}
