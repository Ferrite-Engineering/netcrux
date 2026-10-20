// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';

/// NetCrux's three Recent lists, kept inside [AppSettings] under the
/// `netcrux.recent*` string-list keys, so a list saved by an earlier release is
/// read as it is.
///
/// The ordering, the cap, the per-row remove, Clear Recent and the drop of an
/// entry that no longer opens are the shared list's (`crux_workspace`). Every
/// open records itself through `markOpened`, after the open succeeded.

/// Recently opened projects: `.netcrux-project` files, `<design>.crux-project`
/// manifests and designs opened by path.
final CruxRecentList recentProjects = CruxRecentList(
  name: 'recentProjects',
  store: (ref) => _AppSettingsRecentStore(
    ref,
    read: (settings) => settings.recentProjectPaths,
    write: (notifier, paths) => notifier.setRecentProjectPaths(paths),
  ),
);

/// Recently opened HDL source files.
final CruxRecentList recentSources = CruxRecentList(
  name: 'recentSources',
  store: (ref) => _AppSettingsRecentStore(
    ref,
    read: (settings) => settings.recentSourceFilePaths,
    write: (notifier, paths) => notifier.setRecentSourceFilePaths(paths),
  ),
);

/// Recently opened named workspaces.
final CruxRecentList recentWorkspaces = CruxRecentList(
  name: 'recentWorkspaces',
  store: (ref) => _AppSettingsRecentStore(
    ref,
    read: (settings) => settings.recentWorkspacePaths,
    write: (notifier, paths) => notifier.setRecentWorkspacePaths(paths),
  ),
);

/// A [CruxRecentStore] over one list field of [AppSettings]: it loads the
/// field once the settings have resolved and saves through the settings
/// notifier, so the settings codec stays the only writer of the preference key.
class _AppSettingsRecentStore implements CruxRecentStore {
  _AppSettingsRecentStore(this._ref, {required this.read, required this.write});

  final Ref _ref;

  /// The list field this store holds.
  final List<String> Function(AppSettings settings) read;

  /// Saves the list through the settings notifier.
  final Future<void> Function(AppSettingsNotifier notifier, List<String> paths)
  write;

  @override
  Future<List<String>> load() async {
    try {
      final settings = await _ref.read(appSettingsProvider.future);
      return read(settings);
    } on Object {
      return const <String>[];
    }
  }

  @override
  Future<void> save(List<String> entries) =>
      write(_ref.read(appSettingsProvider.notifier), entries);
}
