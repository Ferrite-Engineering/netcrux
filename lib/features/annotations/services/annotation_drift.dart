// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/crux_annotations_core.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/structural_witness.dart';

/// Reads what the element [kind] / [targetId] of [module] is, structurally:
/// the facts a note on it records when written and compares on every load.
///
/// * a cell: its type and every parameter;
/// * a pin: its cell's type and parameters, the pin's direction and width;
/// * a boundary port: its direction and width;
/// * a net: the one output that drives it (a cell pin, with the cell's type,
///   or an input port of the module), or that nothing does.
///
/// Returns `null` for a scope, which has no structure of its own to witness,
/// and for an element [module] does not have.
StructuralWitness? readStructuralWitness(
  Module module, {
  required AnnotationTargetKind kind,
  required String targetId,
}) {
  switch (kind) {
    case AnnotationTargetKind.cell:
      final cell = module.cells[targetId];
      if (cell == null) return null;
      return StructuralWitness(<String, String>{
        'type': cell.type,
        for (final MapEntry(:key, :value) in cell.parameters.entries)
          'param.$key': value,
      });
    case AnnotationTargetKind.port:
      final cellId = cellIdOfPinId(targetId);
      if (cellId == null) return null;
      final cell = module.cells[cellId];
      final pin = targetId.substring(cellId.length + 1);
      final bits = cell?.connections[pin];
      if (cell == null || bits == null) return null;
      return StructuralWitness(<String, String>{
        'type': cell.type,
        for (final MapEntry(:key, :value) in cell.parameters.entries)
          'param.$key': value,
        'pin.direction': cell.portDirections[pin]?.name ?? 'unknown',
        'pin.width': '${bits.length}',
      });
    case AnnotationTargetKind.boundaryPort:
      final port = module.ports[_boundaryPortName(targetId)];
      if (port == null) return null;
      return StructuralWitness(<String, String>{
        'direction': port.direction.name,
        'width': '${port.bits.length}',
      });
    case AnnotationTargetKind.net:
      final netId = netIdOfEdgeId(targetId);
      if (netId == null || !_hasNetBit(module, netId)) return null;
      return StructuralWitness(<String, String>{
        'driver': _driverOf(module, netId),
      });
    case AnnotationTargetKind.scope:
      return null;
  }
}

/// Whether [module] has the element [kind] / [targetId]. A scope is not an
/// element of a module and is never found here.
bool annotationElementExists(
  Module module, {
  required AnnotationTargetKind kind,
  required String targetId,
}) {
  switch (kind) {
    case AnnotationTargetKind.cell:
      return module.cells.containsKey(targetId);
    case AnnotationTargetKind.port:
      final cellId = cellIdOfPinId(targetId);
      if (cellId == null) return false;
      final pin = targetId.substring(cellId.length + 1);
      return module.cells[cellId]?.connections.containsKey(pin) ?? false;
    case AnnotationTargetKind.boundaryPort:
      return module.ports.containsKey(_boundaryPortName(targetId));
    case AnnotationTargetKind.net:
      final netId = netIdOfEdgeId(targetId);
      return netId != null && _hasNetBit(module, netId);
    case AnnotationTargetKind.scope:
      return false;
  }
}

/// The witness a new note on [kind] / [targetId] records, read from the
/// module [moduleName] of [model]; `null` when there is nothing to read
/// (no design loaded, a scope, or an element the module does not have).
StructuralWitness? captureAnnotationWitness(
  NetlistModel? model, {
  required AnnotationTargetKind kind,
  required String targetId,
  required String? moduleName,
}) {
  if (model == null || moduleName == null) return null;
  final module = model.modules[moduleName];
  if (module == null) return null;
  return readStructuralWitness(module, kind: kind, targetId: targetId);
}

/// Each annotation's status against the design on screen: [model], viewed in
/// a scope of module [currentModule]. Keyed by annotation id.
///
/// The decision table is the suite's ([cruxAnnotationStatusOf]); NetCrux
/// supplies what it is asked:
///
/// * **anchored to an element** — every kind but a scope;
/// * **exists in the file** — the element is in the module the note was
///   written in (for a note saved before the module was recorded: in the
///   module on screen, else in any module of the design);
/// * **displayed** — that module is the one on screen, which is how notes
///   follow the scope: a note inside a child module is drawn when that
///   module is open and listed as outside the current scope otherwise;
/// * **witness** — the element's structure now against the one recorded,
///   when a witness was recorded.
///
/// Empty when no design is loaded: an unknown status is not evidence that a
/// note is lost.
Map<String, CruxAnnotationStatus> annotationStatuses(
  Iterable<Annotation> annotations, {
  required NetlistModel? model,
  required String? currentModule,
}) {
  if (model == null) return const <String, CruxAnnotationStatus>{};
  final statuses = <String, CruxAnnotationStatus>{};
  for (final a in annotations) {
    if (a.targetKind == AnnotationTargetKind.scope) {
      statuses[a.id] = CruxAnnotationStatus.unanchoredToRow;
      continue;
    }
    final home = _homeModule(model, a, currentModule);
    final module = home == null ? null : model.modules[home];
    final exists =
        module != null &&
        annotationElementExists(
          module,
          kind: a.targetKind,
          targetId: a.targetId,
        );
    final recorded = a.witness;
    bool? matches;
    if (exists && recorded != null) {
      final now = readStructuralWitness(
        module,
        kind: a.targetKind,
        targetId: a.targetId,
      );
      matches = now == null ? null : recorded.agreesWith(now);
    }
    statuses[a.id] = cruxAnnotationStatusOf(
      anchoredToElement: true,
      existsInFile: exists,
      isDisplayed: currentModule != null && home == currentModule,
      witnessMatches: matches,
    );
  }
  return statuses;
}

/// The module a note's element is read in: the one recorded, or for a note
/// without one, the module on screen when it has the element, else the first
/// module of the design (by name) that does. `null` when none does.
String? _homeModule(
  NetlistModel model,
  Annotation annotation,
  String? currentModule,
) {
  final recorded = annotation.moduleName;
  if (recorded != null) return recorded;
  bool has(String name) {
    final module = model.modules[name];
    return module != null &&
        annotationElementExists(
          module,
          kind: annotation.targetKind,
          targetId: annotation.targetId,
        );
  }

  if (currentModule != null && has(currentModule)) return currentModule;
  final names = model.modules.keys.toList()..sort();
  for (final name in names) {
    if (has(name)) return name;
  }
  return null;
}

String _boundaryPortName(String targetId) => targetId.startsWith('port:')
    ? targetId.substring('port:'.length)
    : targetId;

bool _hasNetBit(Module module, int netId) {
  for (final net in module.nets.values) {
    for (final bit in net.bits) {
      if (bit is NetBit && bit.netId == netId) return true;
    }
  }
  return false;
}

/// What drives bit [netId] in [module], as a witness fact: a cell's output
/// pin (with the cell's type, so swapping the driving cell for another of a
/// different type is drift even when the instance name is reused), an input
/// port of the module, or `none`. When several outputs drive it, the first in
/// name order is recorded, so the fact is stable across loads.
String _driverOf(Module module, int netId) {
  final cellNames = module.cells.keys.toList()..sort();
  for (final name in cellNames) {
    final cell = module.cells[name]!;
    final pins = cell.connections.keys.toList()..sort();
    for (final pin in pins) {
      if (cell.portDirections[pin] != PortDirection.output) continue;
      for (final bit in cell.connections[pin]!) {
        if (bit is NetBit && bit.netId == netId) {
          return 'cell:$name.$pin:${cell.type}';
        }
      }
    }
  }
  final portNames = module.ports.keys.toList()..sort();
  for (final name in portNames) {
    final port = module.ports[name]!;
    if (port.direction == PortDirection.output) continue;
    for (final bit in port.bits) {
      if (bit is NetBit && bit.netId == netId) return 'port:$name';
    }
  }
  return 'none';
}
