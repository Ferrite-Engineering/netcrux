// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Discriminated union of every kind of element the schematic canvas
/// can have selected.
///
/// Value-typed: two equal selections compare equal. Used as the state
/// of the per-canvas selection notifier and the payload of the canvas
/// hit-tester.
@immutable
sealed class SelectedElement {
  const SelectedElement._();

  /// No current selection.
  const factory SelectedElement.none() = SelectedElementNone;

  /// Selection of a cell instance.
  const factory SelectedElement.cell({required String cellId}) =
      SelectedElementCell;

  /// Selection of a port on a cell.
  const factory SelectedElement.port({
    required String cellId,
    required String portId,
    required String portName,
  }) = SelectedElementPort;

  /// Selection of a module boundary port (drawn at the canvas edge).
  const factory SelectedElement.boundaryPort({
    required String portId,
    required String portName,
  }) = SelectedElementBoundaryPort;

  /// Selection of a wire (edge in the laid-out graph).
  const factory SelectedElement.wire({
    required String edgeId,
    required int netId,
  }) = SelectedElementWire;

  /// True for the [SelectedElement.none] sentinel.
  bool get isNone => this is SelectedElementNone;
}

/// No-selection sentinel.
final class SelectedElementNone extends SelectedElement {
  /// Creates a none-sentinel.
  const SelectedElementNone() : super._();

  @override
  bool operator ==(Object other) => other is SelectedElementNone;

  @override
  int get hashCode => 0;
}

/// Cell selection.
final class SelectedElementCell extends SelectedElement {
  /// Selects the cell instance with [cellId].
  const SelectedElementCell({required this.cellId}) : super._();

  /// Cell instance id (matches `SchematicCell.id`).
  final String cellId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SelectedElementCell && other.cellId == cellId);

  @override
  int get hashCode => Object.hash(SelectedElementCell, cellId);
}

/// Port selection on a cell.
final class SelectedElementPort extends SelectedElement {
  /// Creates a port selection.
  const SelectedElementPort({
    required this.cellId,
    required this.portId,
    required this.portName,
  }) : super._();

  /// Cell that hosts the port.
  final String cellId;

  /// Full port id (`<cellName>:<portName>`).
  final String portId;

  /// Bare port name (`A`, `Y`, `CLK`).
  final String portName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SelectedElementPort &&
          other.cellId == cellId &&
          other.portId == portId &&
          other.portName == portName);

  @override
  int get hashCode =>
      Object.hash(SelectedElementPort, cellId, portId, portName);
}

/// Module boundary port selection.
final class SelectedElementBoundaryPort extends SelectedElement {
  /// Creates a boundary port selection.
  const SelectedElementBoundaryPort({
    required this.portId,
    required this.portName,
  }) : super._();

  /// Full id (`port:<name>`).
  final String portId;

  /// Bare port name.
  final String portName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SelectedElementBoundaryPort &&
          other.portId == portId &&
          other.portName == portName);

  @override
  int get hashCode =>
      Object.hash(SelectedElementBoundaryPort, portId, portName);
}

/// Wire selection.
final class SelectedElementWire extends SelectedElement {
  /// Creates a wire selection.
  const SelectedElementWire({required this.edgeId, required this.netId})
    : super._();

  /// Edge id from the laid-out graph.
  final String edgeId;

  /// Underlying Yosys net id this wire carries.
  final int netId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SelectedElementWire &&
          other.edgeId == edgeId &&
          other.netId == netId);

  @override
  int get hashCode => Object.hash(SelectedElementWire, edgeId, netId);
}
