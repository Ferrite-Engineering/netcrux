// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/waveform_source_service.dart';
import 'package:netcrux/domain/models/activity/waveform_source.dart';
import 'package:netcrux/domain/models/activity/waveform_source_event.dart';

/// Riverpod provider exposing the active [WaveformSourceService].
///
/// Open-core resolves this to [NoopWaveformSourceService] so the
/// `Switching Activity Heatmap` panel's empty state renders and the
/// `openWaveformFile` / `closeWaveformFile` actions stay
/// discoverable in the menu bar / palette without the Pro overlay
/// loaded. The Pro overlay registers a concrete
/// `ProWaveformSourceService` (a pure-Dart VCD parser; FST and GHW
/// are not read) via
/// `proTabOverrides`. The Pro implementation is stateful
/// (parsed VCD, current source, lifecycle event stream), so it is
/// registered **per tab**: a root-only registration made every tab
/// share one loaded waveform, and closing the file in one tab closed
/// it in all of them.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override with `.overrideWith` without taking the
/// build_runner generator dep. Matches the
/// [resetDomainAnalysisServiceProvider] /
/// [clockDomainAnalysisServiceProvider] pattern.
final waveformSourceServiceProvider = Provider<WaveformSourceService>(
  (ref) => const NoopWaveformSourceService(),
  name: 'waveformSourceServiceProvider',
);

/// Tracks the currently-loaded [WaveformSource] (or null when no
/// file is loaded). Watches [waveformSourceServiceProvider.events]
/// and updates whenever a load / unload completes.
///
/// Scoped per tab, following its source: the Pro overlay re-binds
/// [waveformSourceServiceProvider] per tab (each tab owns the VCD it
/// loaded), so this derived view must re-bind with it or a tab-scoped
/// read hoists to the root container and watches the root service's
/// events instead of the active tab's. Open-core builds resolve the
/// no-op service in every tab, so the stream is simply always empty.
final currentWaveformSourceProvider = StreamProvider<WaveformSource?>(
  currentWaveformSource,
  name: 'currentWaveformSourceProvider',
);

/// Body of [currentWaveformSourceProvider]. Declared as a named
/// top-level function so the per-tab override list can re-bind the
/// provider without restating the mapping.
Stream<WaveformSource?> currentWaveformSource(Ref ref) {
  final service = ref.watch(waveformSourceServiceProvider);
  return service.events.map<WaveformSource?>((event) {
    switch (event) {
      case WaveformSourceLoadedEvent(:final source):
        return source;
      case WaveformSourceUnloadedEvent():
        return null;
      case WaveformSourceLoadFailedEvent():
        return service.currentSource;
    }
  }).distinct();
}
