// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';

/// A register (flip-flop) that carries no reset — its state is never
/// assigned inside any reset branch, so it powers up in an unknown (`X`)
/// value and holds it until the first functional clock edge writes a
/// defined value.
///
/// Surfaced by the reset-domain analysis as a distinct finding class,
/// separate from a [ResetCrossing]: a crossing is a *relationship* between
/// two reset domains, whereas an unreset register is the *absence* of any
/// reset on a flop. It is reported only when the design has at least one
/// reset domain — a fully reset-less design (a pure datapath, a testbench)
/// is not flagged, since a missing reset is only suspicious when resets
/// exist elsewhere.
@immutable
class UnresetRegister {
  /// Creates an unreset-register finding.
  const UnresetRegister({
    required this.registerId,
    required this.registerName,
    required this.width,
  });

  /// JSON round-trip constructor.
  factory UnresetRegister.fromJson(Map<String, Object?> json) {
    final idRaw = json['registerId'];
    return UnresetRegister(
      registerId: idRaw is Map<String, Object?>
          ? ElementId.fromJson(idRaw)
          : const ElementId(kind: ElementKind.signal, path: ''),
      registerName: json['registerName']?.toString() ?? '',
      width: (json['width'] as num?)?.toInt() ?? 1,
    );
  }

  /// Cross-suite identifier for the register cell that lacks a reset. The
  /// schematic overlay highlights it when the finding row is selected.
  final ElementId registerId;

  /// Human-readable name of the register (for panel display) — its `Q`
  /// output net / port name when resolvable, else the raw cell name.
  final String registerName;

  /// Width of the register in bits (`Q` output width). At least 1.
  final int width;

  /// JSON map suitable for fixture round-trip.
  Map<String, Object?> toJson() => <String, Object?>{
    'registerId': registerId.toJson(),
    'registerName': registerName,
    'width': width,
  };

  /// Returns a copy with the given fields replaced.
  UnresetRegister copyWith({
    ElementId? registerId,
    String? registerName,
    int? width,
  }) => UnresetRegister(
    registerId: registerId ?? this.registerId,
    registerName: registerName ?? this.registerName,
    width: width ?? this.width,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnresetRegister &&
          runtimeType == other.runtimeType &&
          registerId == other.registerId &&
          registerName == other.registerName &&
          width == other.width;

  @override
  int get hashCode => Object.hash(registerId, registerName, width);

  @override
  String toString() =>
      'UnresetRegister(name: $registerName, width: $width, '
      'id: ${registerId.path})';
}
