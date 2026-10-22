// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/crux_annotations_core.dart';
import 'package:meta/meta.dart';

/// What an annotated schematic element *was* when the note was written: its
/// structure, as a flat set of named facts.
///
/// NetCrux's [CruxAnnotationWitness]. For a cell, its type and its
/// parameters; for a pin, its cell's type, the pin's direction and width; for
/// a boundary port, its direction and width; for a net, what drives it. A
/// scope has no witness. After a re-elaboration the facts are read again from
/// the new design and compared: any difference marks the note drifted, which
/// says the claim it makes was about a different structure and needs
/// re-checking.
///
/// Facts rather than a hash, so the comparison stays explainable and a
/// difference can be named in the user's terms if a later release wants to.
@immutable
final class StructuralWitness implements CruxAnnotationWitness {
  /// Creates a witness from [facts], copied and frozen.
  StructuralWitness(Map<String, String> facts)
    : facts = Map<String, String>.unmodifiable(facts);

  /// Reads a witness back from [toJson], or `null` when the payload is
  /// unusable. A malformed witness is dropped rather than failing the
  /// annotation: the note then has nothing to drift against, which is the
  /// state it would have had if the witness had never been captured.
  static StructuralWitness? fromJson(Object? json) {
    if (json is! Map) return null;
    final raw = json['facts'];
    if (raw is! Map) return null;
    final facts = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! String) return null;
      facts[key] = value;
    }
    if (facts.isEmpty) return null;
    return StructuralWitness(facts);
  }

  /// The named facts, for example `{'type': r'$dff', 'param.WIDTH': '8'}`.
  final Map<String, String> facts;

  /// Whether [current], read from the design as it is now, says the same
  /// thing. Order does not matter; every fact must be present and equal.
  bool agreesWith(StructuralWitness current) {
    if (current.facts.length != facts.length) return false;
    for (final entry in facts.entries) {
      if (current.facts[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'facts': <String, String>{
      for (final key in facts.keys.toList()..sort()) key: facts[key]!,
    },
  };

  @override
  bool operator ==(Object other) =>
      other is StructuralWitness && agreesWith(other);

  @override
  int get hashCode => Object.hashAllUnordered(
    facts.entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => 'StructuralWitness($facts)';
}
