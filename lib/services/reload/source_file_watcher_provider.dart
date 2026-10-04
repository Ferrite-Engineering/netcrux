// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_file_watcher/crux_file_watcher.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'source_file_watcher_provider.g.dart';

/// How often each watched source file's size and modification time are also
/// read, to catch an edit the platform watch did not report.
///
/// On macOS the directory watch behind [FileWatcherService] can stop
/// delivering events for the rest of the process, with no error, and a new
/// watch hears nothing either (crux-shared#25). Watching alone, the reload
/// prompt then appeared once and never again. A stat of each source file a
/// second is cheap next to that.
const Duration kSourceFilePollInterval = Duration(seconds: 1);

/// The platform watch [SourceFileWatcher] hands each [FileWatcherService].
///
/// Null, the default, is `crux_file_watcher`'s own directory watch. Tests
/// override it to stand in a platform watch that misbehaves the way a real
/// one has been measured to.
@Riverpod(keepAlive: true)
WatchFactory? sourceFileWatchFactory(Ref ref) => null;

/// The poll interval [SourceFileWatcher] gives each [FileWatcherService]:
/// [kSourceFilePollInterval] in the app.
///
/// A widget test that opens a design and is not about reloading overrides it
/// with null. The poll is a periodic timer, and the per-tab containers that
/// own it are disposed after `flutter_test` checks for pending timers.
@Riverpod(keepAlive: true)
Duration? sourceFilePollInterval(Ref ref) => kSourceFilePollInterval;

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
///
/// Each file is also polled every [sourceFilePollIntervalProvider], so an edit the
/// platform watch misses still arrives.
@Riverpod(keepAlive: true)
class SourceFileWatcher extends _$SourceFileWatcher {
  final List<FileWatcherService> _watchers = <FileWatcherService>[];

  @override
  void build() {
    ref
      ..listen<NetcruxProject>(
        currentProjectProvider,
        (previous, next) => _retarget(next.sourceFiles),
        fireImmediately: true,
      )
      ..onDispose(_disposeWatchers);
  }

  void _disposeWatchers() {
    for (final w in _watchers) {
      w.dispose();
    }
    _watchers.clear();
  }

  void _retarget(List<String> paths) {
    _disposeWatchers();
    if (paths.isEmpty) return;
    final watchFactory = ref.read(sourceFileWatchFactoryProvider);
    final pollInterval = ref.read(sourceFilePollIntervalProvider);
    for (final path in paths) {
      final svc = FileWatcherService(
        watchFactory: watchFactory,
        pollInterval: pollInterval,
      );
      svc.events.listen((event) => _onChange(<FileWatchEvent>[event]));
      svc.startWatching(path);
      _watchers.add(svc);
    }
  }

  void _onChange(List<FileWatchEvent> events) {
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
