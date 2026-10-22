// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/crux_annotations_core.dart';
import 'package:meta/meta.dart';

/// The kind of schematic element an [AnnotationTarget] names.
///
/// Kept narrow on purpose: only schematic-visible elements get a stable
/// targetId in a persisted annotation. Generate-block expansions or
/// hierarchy nodes that change across re-elaboration would be unstable
/// targets, so they are deliberately excluded.
enum AnnotationTargetKind {
  /// A schematic cell (a Yosys cell instance — e.g. `u_alu`).
  cell,

  /// A pin on a cell (e.g. `u_alu:A`).
  port,

  /// A boundary port on the active scope (e.g. `port:reset_n`).
  boundaryPort,

  /// A wire / net (e.g. the edge id `e_4` referencing Yosys net 4).
  net,

  /// A hierarchical scope navigated to by name path (e.g.
  /// `top.cpu.alu`). An annotation of this kind does not pin a specific
  /// element inside the scope — it is about the scope itself.
  scope,
}

/// Parses an [AnnotationTargetKind] from its persisted name, or `null` for
/// a name this build does not know.
AnnotationTargetKind? annotationTargetKindFromName(Object? name) {
  if (name is! String) return null;
  for (final kind in AnnotationTargetKind.values) {
    if (kind.name == name) return kind;
  }
  return null;
}

/// A schematic element an annotation is on: the pre-populated target for Add
/// Annotation, and the anchor of a written note.
///
/// When non-null on the opener, the new annotation starts with the target
/// fields already filled in (commonly because the user invoked the action
/// from a schematic context menu on a specific element). When null, the
/// opener falls back to the active schematic selection.
///
/// This is NetCrux's [CruxAnnotationAnchor]: data coordinates, an element of a
/// module, never a position on the canvas. A scope names no single element.
@immutable
class AnnotationTarget implements CruxAnnotationAnchor {
  /// Creates a target descriptor.
  const AnnotationTarget({required this.kind, required this.targetId});

  /// Which kind of schematic element this targets.
  final AnnotationTargetKind kind;

  /// The stable target id (cell instance name, pin `cell:port`,
  /// `port:<name>` for boundary ports, edge id `e_N` for nets, dotted
  /// scope path for scopes).
  final String targetId;

  @override
  String? get elementId => kind == AnnotationTargetKind.scope ? null : targetId;

  /// The two fields an annotation record already carries flat, under the
  /// same keys.
  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'targetKind': kind.name,
    'targetId': targetId,
  };

  @override
  bool operator ==(Object other) =>
      other is AnnotationTarget &&
      other.kind == kind &&
      other.targetId == targetId;

  @override
  int get hashCode => Object.hash(kind, targetId);
}
