// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/glowing_app_icon.dart';
import 'package:netcrux/shared/widgets/netcrux_suite_footer.dart';
import 'package:netcrux/shared/widgets/netcrux_suite_peers.dart';
import 'package:path/path.dart' as p;

/// Renders the package's [`EmptyCanvasState`] shell with NetCrux-specific
/// content slots: recent projects, recent source files, recent named
/// workspaces, and the three primary Open actions (Open Project, Open
/// Source Files, Open Workspace).
///
/// Watches [`appSettingsProvider`] so the recent lists refresh as the user
/// opens / clears them. Every action dispatches through caller-supplied
/// callbacks so this widget stays free of file-picker / workspace-mutation
/// dependencies — the wiring layer in `ProjectTabContent` / the home-route
/// owns those.
class EmptyCanvasContent extends ConsumerWidget {
  /// Creates the empty-canvas content.
  const EmptyCanvasContent({
    required this.onOpenProject,
    required this.onOpenSourceFiles,
    required this.onOpenWorkspace,
    required this.onPickRecentProject,
    required this.onPickRecentSourceFile,
    required this.onPickRecentWorkspace,
    required this.onClearRecent,
    super.key,
  });

  /// Fired when the Open Project button is tapped.
  final VoidCallback onOpenProject;

  /// Fired when the Open Source Files button is tapped.
  final VoidCallback onOpenSourceFiles;

  /// Fired when the Open Workspace button is tapped.
  final VoidCallback onOpenWorkspace;

  /// Fired when a recent-project list entry is tapped.
  final ValueChanged<String> onPickRecentProject;

  /// Fired when a recent-source-file list entry is tapped.
  final ValueChanged<String> onPickRecentSourceFile;

  /// Fired when a recent-workspace list entry is tapped.
  final ValueChanged<String> onPickRecentWorkspace;

  /// Fired when the Clear Recent button is tapped.
  final VoidCallback onClearRecent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final projects = settings?.recentProjectPaths ?? const <String>[];
    final sources = settings?.recentSourceFilePaths ?? const <String>[];
    final workspaces = settings?.recentWorkspacePaths ?? const <String>[];
    final hasAnyRecent =
        projects.isNotEmpty || sources.isNotEmpty || workspaces.isNotEmpty;
    // The running version, shown as a muted line under the subtitle. On web
    // there is no native menu bar, so this is the only always-visible place a
    // user can read the version without knowing the palette / overflow About
    // entry points. Resolves in milliseconds; renders nothing until then.
    final version = ref.watch(aboutBuildInfoProvider).value?.version;

    return EmptyCanvasState(
      header: const GlowingAppIcon(size: 72),
      title: l10n.emptyCanvasTitle,
      subtitle: l10n.emptyCanvasSubtitle,
      versionLabel: version == null ? null : l10n.emptyCanvasVersion(version),
      recentFilesSection: _RecentList(
        header: l10n.emptyCanvasRecentProjects,
        paths: projects,
        onTap: onPickRecentProject,
        emptyLabel: l10n.emptyCanvasNoRecentProjects,
      ),
      recentWorkspacesSection: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _RecentList(
            header: l10n.emptyCanvasRecentSources,
            paths: sources,
            onTap: onPickRecentSourceFile,
            emptyLabel: l10n.emptyCanvasNoRecentSources,
          ),
          if (workspaces.isNotEmpty) ...[
            const SizedBox(height: 16),
            _RecentList(
              header: l10n.workspaceOpenWorkspaceTitle,
              paths: workspaces,
              onTap: onPickRecentWorkspace,
              emptyLabel: '',
            ),
          ],
          if (hasAnyRecent) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onClearRecent,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.emptyCanvasClearRecent),
              ),
            ),
          ],
        ],
      ),
      primaryActions: <Widget>[
        FilledButton.icon(
          onPressed: onOpenProject,
          icon: const Icon(Icons.folder_open),
          label: Text(l10n.actionOpenProject),
        ),
        OutlinedButton.icon(
          onPressed: onOpenSourceFiles,
          icon: const Icon(Icons.insert_drive_file_outlined),
          label: Text(l10n.actionOpenSourceFiles),
        ),
        OutlinedButton.icon(
          onPressed: onOpenWorkspace,
          icon: const Icon(Icons.workspaces_outline),
          label: Text(l10n.workspaceOpenWorkspaceTitle),
        ),
      ],
      // Says that the other three products exist, to a user who arrived at
      // this one and has no reason to know.
      // What the other three products do for someone who is here,
      // reading a schematic. Above the suite line, which is the quieter
      // version of the same statement.
      peers: const NetCruxSuitePeers(),
      footer: const NetCruxSuiteFooter(),
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.header,
    required this.paths,
    required this.onTap,
    required this.emptyLabel,
  });

  final String header;
  final List<String> paths;
  final ValueChanged<String> onTap;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(header, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (paths.isEmpty)
          Text(
            emptyLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: paths.length,
              itemBuilder: (context, index) {
                final path = paths[index];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    p.basename(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    p.dirname(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onTap(path),
                );
              },
            ),
          ),
      ],
    );
  }
}
