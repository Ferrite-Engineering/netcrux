// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/activity/waveform_format.dart';

/// Stable identity of an opened waveform file.
///
/// Returned by [WaveformSourceService.loadWaveform] and consumed by
/// [ActivityAnalysisService.analyze] to key per-source caches.
///
/// The [fingerprint] is a cheap stable identifier derived from the
/// file's size + a sample of its head bytes (the Pro loader uses
/// SHA-256 of the first 64 KiB plus the file size). Two different
/// physical files will (in practice) yield two different fingerprints
/// even when they have the same name on disk.
@immutable
class WaveformSource {
  /// Creates a waveform source descriptor.
  const WaveformSource({
    required this.filePath,
    required this.format,
    required this.loadedAt,
    required this.fingerprint,
    this.fileSizeBytes = 0,
  });

  /// JSON round-trip constructor — covers fixture tests.
  factory WaveformSource.fromJson(Map<String, Object?> json) {
    return WaveformSource(
      filePath: json['filePath']?.toString() ?? '',
      format: WaveformFormat.fromJsonString(
        json['format']?.toString() ?? '',
      ),
      loadedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['loadedAtMillis'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      fingerprint: json['fingerprint']?.toString() ?? '',
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  /// Absolute path to the loaded file.
  final String filePath;

  /// Detected file format.
  final WaveformFormat format;

  /// Wall-clock instant the file was opened. Used by the panel
  /// footer's "Loaded at HH:MM:SS" readout.
  final DateTime loadedAt;

  /// Cheap stable identifier (hex string). Used by
  /// [ActivityAnalysisService] to key its per-source analysis cache.
  final String fingerprint;

  /// File size in bytes. Surfaced in the panel footer's "12.3 MiB"
  /// readout. Optional; 0 when the loader couldn't stat the file.
  final int fileSizeBytes;

  /// Returns a copy with the given fields replaced.
  WaveformSource copyWith({
    String? filePath,
    WaveformFormat? format,
    DateTime? loadedAt,
    String? fingerprint,
    int? fileSizeBytes,
  }) => WaveformSource(
    filePath: filePath ?? this.filePath,
    format: format ?? this.format,
    loadedAt: loadedAt ?? this.loadedAt,
    fingerprint: fingerprint ?? this.fingerprint,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
  );

  /// JSON map suitable for fixture round-trip.
  Map<String, Object?> toJson() => <String, Object?>{
    'filePath': filePath,
    'format': format.toJsonString(),
    'loadedAtMillis': loadedAt.toUtc().millisecondsSinceEpoch,
    'fingerprint': fingerprint,
    'fileSizeBytes': fileSizeBytes,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WaveformSource) return false;
    return filePath == other.filePath &&
        format == other.format &&
        loadedAt == other.loadedAt &&
        fingerprint == other.fingerprint &&
        fileSizeBytes == other.fileSizeBytes;
  }

  @override
  int get hashCode => Object.hash(
    filePath,
    format,
    loadedAt,
    fingerprint,
    fileSizeBytes,
  );

  @override
  String toString() =>
      'WaveformSource('
      'file: $filePath, '
      'format: ${format.name}, '
      'fingerprint: $fingerprint, '
      'size: ${fileSizeBytes}B)';
}
