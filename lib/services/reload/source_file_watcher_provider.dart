// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_file_watcher/crux_file_watcher.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'source_file_watcher_provider.g.dart';

/// Per-source-file watcher that re-elaborates the design on change.
///
/// Watches every entry in [currentProjectProvider]'s `sourceFiles`
/// via the cross-suite [FileWatcherService] (`crux_file_watcher`).
/// On change (debounced 500 ms by `FileWatcherService` itself),
/// consults [AutoReloadMode] from [AppSettings]:
///
/// - `auto` → immediately calls
///   [LoadedNetlistNotifier]-equivalent `ref.invalidate(loadedNetlistProvider)`
///   so elaboration re-runs.
/// - `prompt` → publishes a [SourceChangedEvent] on the
///   [sourceReloadEventsProvider] stream so the UI can prompt the
///   user.
/// - `off` → ignores the change entirely (the watcher still runs so
///   switching the setting back to auto/prompt picks up immediately).
@Riverpod(keepAlive: true)
class SourceFileWatcher extends _$SourceFileWatcher {
  final List<FileWatcherService> _watchers = <FileWatcherService>[];
  StreamSubscription<List<FileWatchEvent>>? _aggregateSub;
  final StreamController<List<FileWatchEvent>> _aggregate =
      StreamController<List<FileWatchEvent>>.broadcast();

  @override
  void build() {
    ref.listen<NetcruxProject>(
      currentProjectProvider,
      (previous, next) => _retarget(next.sourceFiles),
      fireImmediately: true,
    );
    _aggregateSub = _aggregate.stream.listen(_onAggregateBatch);
    ref.onDispose(() {
      for (final w in _watchers) {
        w.dispose();
      }
      _watchers.clear();
      unawaited(_aggregateSub?.cancel());
      unawaited(_aggregate.close());
    });
  }

  void _retarget(List<String> paths) {
    for (final w in _watchers) {
      w.dispose();
    }
    _watchers.clear();
    if (paths.isEmpty) return;
    for (final path in paths) {
      final svc = FileWatcherService();
      svc.events.listen((event) {
        _aggregate.add(<FileWatchEvent>[event]);
      });
      svc.startWatching(path);
      _watchers.add(svc);
    }
  }

  void _onAggregateBatch(List<FileWatchEvent> events) {
    final mode =
        ref.read(appSettingsProvider).value?.core.autoReloadMode ??
        AutoReloadMode.auto;
    switch (mode) {
      case AutoReloadMode.auto:
        ref.invalidate(loadedNetlistProvider);
      case AutoReloadMode.prompt:
        ref.read(sourceReloadEventsProvider.notifier).publish(events.length);
      case AutoReloadMode.off:
        // Drop on the floor.
        break;
    }
  }
}

/// Snapshot of the last "files changed" notification, surfaced to UI
/// when [AutoReloadMode.prompt] is active. Reset to `null` by the UI
/// after it acks (or by the next reload event, which supersedes it).
@Riverpod(keepAlive: true)
class SourceReloadEvents extends _$SourceReloadEvents {
  @override
  int? build() => null;

  /// Publishes that [count] files just changed. UI watches and shows a
  /// snackbar.
  // ignore: use_setters_to_change_properties
  void publish(int count) {
    state = count;
  }

  /// UI calls this once it's surfaced the prompt to clear it.
  void clear() {
    if (state == null) return;
    state = null;
  }
}
