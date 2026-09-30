// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';

/// Computes the structural golden model for a parsed [NetlistModel] — the
/// committed `*.expected_netlist.json` companion that lets a parser
/// regression be caught by a `git diff`, Yosys-free.
///
/// The broken-out counts (`cellCount`, `portCount`, `netCount`,
/// `cellTypeHistogram`) make a *partial* regression legible in a diff (you
/// see `cellCount 10000 → 9999`, not an opaque hash mismatch); the
/// [fingerprint] is the cheap exact-equality net over the canonical structure.
class NetlistGolden {
  const NetlistGolden._();

  /// Builds the golden map for [model]. [source] is informational (the RTL
  /// file the design came from); it does not affect the [fingerprint].
  static Map<String, Object?> compute(
    NetlistModel model, {
    required String source,
  }) {
    final names = model.modules.keys.toList()..sort();
    final modules = <Map<String, Object?>>[
      for (final name in names) _moduleGolden(name, model.modules[name]!),
    ];
    final topName =
        model.topModule?.name ?? (names.isNotEmpty ? names.first : '');
    return <String, Object?>{
      'source': source,
      'topModule': topName,
      'moduleCount': model.modules.length,
      'modules': modules,
      'fingerprint': 'fnv1a:${_fingerprint(modules).toRadixString(16)}',
    };
  }

  static Map<String, Object?> _moduleGolden(String name, Module module) {
    final histogram = <String, int>{};
    for (final cell in module.cells.values) {
      histogram[cell.type] = (histogram[cell.type] ?? 0) + 1;
    }
    final sortedTypes = histogram.keys.toList()..sort();
    return <String, Object?>{
      'name': name,
      'cellCount': module.cells.length,
      'portCount': module.ports.length,
      'netCount': module.nets.length,
      'cellTypeHistogram': <String, int>{
        for (final type in sortedTypes) type: histogram[type]!,
      },
    };
  }

  /// 32-bit FNV-1a over the canonical structural string of [modules]
  /// (already sorted by name, each histogram sorted by type). Stable across
  /// runs and platforms; ignores `creator` and net/port/cell *names* so a
  /// cosmetic rename does not churn the fingerprint while a structural change
  /// (a dropped cell, a changed type) does.
  static int _fingerprint(List<Map<String, Object?>> modules) {
    final buffer = StringBuffer();
    for (final m in modules) {
      buffer
        ..write(m['name'])
        ..write('|c=')
        ..write(m['cellCount'])
        ..write('|p=')
        ..write(m['portCount'])
        ..write('|n=')
        ..write(m['netCount'])
        ..write('|h=');
      final histogram = m['cellTypeHistogram']! as Map<String, int>;
      for (final entry in histogram.entries) {
        buffer
          ..write(entry.key)
          ..write(':')
          ..write(entry.value)
          ..write(',');
      }
      buffer.write(';');
    }
    return fnv1a32(buffer.toString());
  }

  /// 32-bit FNV-1a hash of [input]'s UTF-16 code units. Exposed so tooling
  /// and tests share the exact algorithm.
  static int fnv1a32(String input) {
    var hash = 0x811c9dc5;
    for (final code in input.codeUnits) {
      hash ^= code & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
      if (code > 0xff) {
        hash ^= (code >> 8) & 0xff;
        hash = (hash * 0x01000193) & 0xffffffff;
      }
    }
    return hash;
  }
}
