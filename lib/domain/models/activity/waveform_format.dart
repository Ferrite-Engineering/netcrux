// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// File format identifier for a waveform source consumed by the
/// Switching Activity Heatmap.
///
/// v1 ships with [vcd] only (the open-core ProWaveformSourceService
/// uses a pure-Dart VCD parser). Future Pro consolidation with the
/// cross-suite `wellen_ffi` package (today living in
/// `wavecrux/native/wellen_ffi/`) will add [fst] and [ghw] without
/// touching this enum — only the loader implementation changes.
enum WaveformFormat {
  /// IEEE Std 1800-2023 Value Change Dump. ASCII text. The format
  /// every open-source simulator (Verilator, Icarus, GHDL) writes.
  vcd,

  /// Fast Signal Trace — GTKWave's binary format. Parser lives in
  /// `wellen`; NetCrux v1 surfaces format detection but the Pro
  /// loader raises [UnimplementedWaveformLoad] until the wellen
  /// integration lands.
  fst,

  /// GHDL Waveform — nine-state VHDL native format. Same status as
  /// [fst].
  ghw;

  /// Stable JSON tag.
  String toJsonString() => name;

  /// Parses a tag back to a [WaveformFormat]. Unknown values map to
  /// [vcd] for forward-compat (the most permissive fallback).
  static WaveformFormat fromJsonString(String raw) {
    for (final f in WaveformFormat.values) {
      if (f.name == raw) return f;
    }
    return WaveformFormat.vcd;
  }

  /// Returns the [WaveformFormat] inferred from the file path's
  /// extension. Falls back to [vcd] for unknown extensions so the
  /// loader can still attempt to open the file rather than silently
  /// rejecting it.
  static WaveformFormat fromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.fst')) return WaveformFormat.fst;
    if (lower.endsWith('.ghw')) return WaveformFormat.ghw;
    return WaveformFormat.vcd;
  }
}
