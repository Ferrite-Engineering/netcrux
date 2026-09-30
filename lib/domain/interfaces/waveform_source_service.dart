// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/activity/waveform_source.dart';
import 'package:netcrux/domain/models/activity/waveform_source_event.dart';

/// Raised by [WaveformSourceService.loadWaveform] when the loader
/// rejects the file outright (unsupported format, missing file,
/// permission denied, corrupt header, hierarchy mismatch against the
/// active netlist).
///
/// Distinct from a transient failure: the open-core no-op loader
/// always raises [UnimplementedWaveformLoad] (a subclass) so the
/// dispatch path is exercised in tests without the Pro overlay
/// present.
class WaveformLoadException implements Exception {
  /// Creates a load exception.
  const WaveformLoadException(this.filePath, this.message);

  /// Path the caller attempted to open.
  final String filePath;

  /// One-line user-facing description of why the load failed.
  final String message;

  @override
  String toString() =>
      'WaveformLoadException(file: $filePath, reason: $message)';
}

/// Sentinel raised by [NoopWaveformSourceService.loadWaveform]
/// indicating that the open-core build cannot load waveforms. The
/// Pro overlay registers a concrete loader that uses a pure-Dart VCD
/// parser.
class UnimplementedWaveformLoad extends WaveformLoadException {
  /// Creates the unimplemented sentinel.
  const UnimplementedWaveformLoad(String filePath)
    : super(
        filePath,
        'Waveform loading requires the NetCrux Pro overlay.',
      );
}

/// Extension-point service powering the Switching Activity
/// Heatmap's file lifecycle.
///
/// Open-core ships [NoopWaveformSourceService] as the registered
/// default: [loadWaveform] throws [UnimplementedWaveformLoad],
/// [queryNetTransitions] returns an empty iterable, and [events] is
/// the empty stream. The Pro overlay registers a concrete
/// `ProWaveformSourceService` via `proOverrides` that parses VCD
/// (and, in a future revision, FST / GHW via `wellen_ffi`).
///
/// Lives in `lib/domain/interfaces/` like every other analysis seam; the
/// Riverpod accessor `waveformSourceServiceProvider` lives in
/// `lib/services/waveform/`.
abstract interface class WaveformSourceService {
  /// Opens [filePath]. Returns the canonical [WaveformSource]
  /// descriptor the analyzer later keys its cache against. Replaces
  /// any previously-loaded source — only one source is live at a
  /// time per service instance.
  ///
  /// Raises [WaveformLoadException] on any failure. The Pro
  /// implementation surfaces structured codes (`missing_file`,
  /// `unsupported_format`, `parse_error`, `hierarchy_mismatch`) in
  /// [WaveformLoadException.message].
  Future<WaveformSource> loadWaveform(String filePath);

  /// Closes the currently-loaded source (if any). No-op when none is
  /// loaded.
  Future<void> unloadWaveform();

  /// Returns the value transitions for [netPath] inside
  /// `[startNs, endNs)`. When [startNs] / [endNs] are null the loader
  /// returns the full per-net change list.
  ///
  /// Each tuple is `(timeNs, value)`. `value` is the canonical
  /// signal-value string the parser emitted ("0", "1", "x", "z",
  /// "b001011" for vectors, etc.). The caller is responsible for
  /// interpreting these per the net's bit width.
  ///
  /// Returns an empty iterable when no source is loaded, when the
  /// net is unknown to the loaded hierarchy, or when no transitions
  /// fall inside the window.
  Future<Iterable<(int timeNs, String value)>> queryNetTransitions(
    String netPath, {
    int? startNs,
    int? endNs,
  });

  /// Hierarchical net paths the loaded source exposes. Useful for
  /// the analyzer's "walk every net" pass and for diagnostic /
  /// hierarchy-mismatch reporting. Returns an empty iterable when no
  /// source is loaded.
  Iterable<String> get loadedNetPaths;

  /// End-time of the loaded simulation in nanoseconds. Used by the
  /// analyzer when [WaveformTimeRange.fullSimulationSentinel] is
  /// passed. Returns 0 when no source is loaded.
  int get sourceEndNs;

  /// The currently-loaded source, or null when none is loaded.
  WaveformSource? get currentSource;

  /// Broadcast stream of lifecycle events. Surfaces every successful
  /// load, every unload, and every failed-load attempt. Subscribers
  /// (the per-tab `currentWaveformSourceProvider` and the activity
  /// analysis service) listen to invalidate their caches.
  Stream<WaveformSourceEvent> get events;
}

/// Open-core default: every load throws [UnimplementedWaveformLoad],
/// every query returns empty, [events] is the empty stream.
class NoopWaveformSourceService implements WaveformSourceService {
  /// Creates the no-op service.
  const NoopWaveformSourceService();

  @override
  Future<WaveformSource> loadWaveform(String filePath) async {
    throw UnimplementedWaveformLoad(filePath);
  }

  @override
  Future<void> unloadWaveform() async {}

  @override
  Future<Iterable<(int timeNs, String value)>> queryNetTransitions(
    String netPath, {
    int? startNs,
    int? endNs,
  }) async => const <(int, String)>[];

  @override
  Iterable<String> get loadedNetPaths => const <String>[];

  @override
  int get sourceEndNs => 0;

  @override
  WaveformSource? get currentSource => null;

  @override
  Stream<WaveformSourceEvent> get events =>
      const Stream<WaveformSourceEvent>.empty();
}
