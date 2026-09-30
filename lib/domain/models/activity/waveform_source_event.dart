// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/activity/waveform_source.dart';

/// Lifecycle event emitted by [WaveformSourceService.events].
///
/// Three variants cover the full load lifecycle:
///   * [WaveformSourceLoadedEvent] — a file was opened successfully.
///   * [WaveformSourceUnloadedEvent] — the active file was closed.
///   * [WaveformSourceLoadFailedEvent] — an open attempt failed.
@immutable
sealed class WaveformSourceEvent {
  /// Const base ctor.
  const WaveformSourceEvent();
}

/// A waveform file was opened successfully.
@immutable
class WaveformSourceLoadedEvent extends WaveformSourceEvent {
  /// Creates the loaded event.
  const WaveformSourceLoadedEvent({required this.source});

  /// The descriptor of the newly-loaded source.
  final WaveformSource source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WaveformSourceLoadedEvent && other.source == source);

  @override
  int get hashCode => Object.hash(runtimeType, source);

  @override
  String toString() => 'WaveformSourceLoadedEvent($source)';
}

/// The active waveform was closed.
@immutable
class WaveformSourceUnloadedEvent extends WaveformSourceEvent {
  /// Creates the unloaded event.
  const WaveformSourceUnloadedEvent({required this.previousFilePath});

  /// Absolute path of the file that was just closed. Surfaced so
  /// listeners can clear per-file caches keyed by path.
  final String previousFilePath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WaveformSourceUnloadedEvent &&
          other.previousFilePath == previousFilePath);

  @override
  int get hashCode => Object.hash(runtimeType, previousFilePath);

  @override
  String toString() => 'WaveformSourceUnloadedEvent($previousFilePath)';
}

/// A load attempt failed.
@immutable
class WaveformSourceLoadFailedEvent extends WaveformSourceEvent {
  /// Creates the failed-load event.
  const WaveformSourceLoadFailedEvent({
    required this.filePath,
    required this.message,
  });

  /// The path the user attempted to open.
  final String filePath;

  /// Short user-facing description of the failure. Surfaced by the
  /// panel's snackbar.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WaveformSourceLoadFailedEvent &&
          other.filePath == filePath &&
          other.message == message);

  @override
  int get hashCode => Object.hash(runtimeType, filePath, message);

  @override
  String toString() => 'WaveformSourceLoadFailedEvent($filePath, "$message")';
}
