// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/features/workspace/providers/recent_lists.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/glowing_app_icon.dart';
import 'package:netcrux/shared/widgets/netcrux_suite_footer.dart';
import 'package:netcrux/shared/widgets/netcrux_suite_peers.dart';

/// Renders the package's [`EmptyCanvasState`] shell with NetCrux-specific
/// content slots: recent projects, recent source files, recent named
/// workspaces, and the three primary Open actions (Open Project, Open
/// Source Files, Open Workspace).
///
/// Each recent list is the shared `CruxRecentListSection` over the matching
/// list in `recent_lists.dart`, so a row whose file is gone is greyed and says
/// so, opening it drops it and reports why, and every row has a remove button
/// and every list a Clear Recent button. Every action dispatches through
/// caller-supplied callbacks so this widget stays free of file-picker /
/// workspace-mutation dependencies — the wiring layer in `ProjectTabContent` /
/// the home-route owns those.
class EmptyCanvasContent extends ConsumerWidget {
  /// Creates the empty-canvas content.
  const EmptyCanvasContent({
    required this.onOpenProject,
    required this.onOpenSourceFiles,
    required this.onOpenWorkspace,
    required this.onPickRecentProject,
    required this.onPickRecentSourceFile,
    required this.onPickRecentWorkspace,
    super.key,
  });

  /// Fired when the Open Project button is tapped.
  final VoidCallback onOpenProject;

  /// Fired when the Open Source Files button is tapped.
  final VoidCallback onOpenSourceFiles;

  /// Fired when the Open Workspace button is tapped.
  final VoidCallback onOpenWorkspace;

  /// Opens a recent-project list entry that still exists. A load failure
  /// reports itself.
  final Future<void> Function(String path) onPickRecentProject;

  /// Opens a recent-source-file list entry that still exists.
  final Future<void> Function(String path) onPickRecentSourceFile;

  /// Opens a recent-workspace list entry that still exists.
  final Future<void> Function(String path) onPickRecentWorkspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final hasWorkspaces = ref.watch(recentWorkspaces.provider).isNotEmpty;
    // The running version, shown as a muted line under the subtitle. On web
    // there is no native menu bar, so this is the only always-visible place a
    // user can read the version without knowing the palette / overflow About
    // entry points. Resolves in milliseconds; renders nothing until then.
    final version = ref.watch(aboutBuildInfoProvider).value?.version;

    // A missing file is dropped and reported by the section; a load failure
    // reports itself, so the wrapper only answers "does it exist".
    Future<bool> Function(String path) opening(
      CruxRecentList list,
      Future<void> Function(String path) open,
    ) {
      final exists = ref.read(list.existsProvider);
      return (path) async {
        if (!exists(path)) return false;
        await open(path);
        return true;
      };
    }

    return EmptyCanvasState(
      header: const GlowingAppIcon(size: 72),
      title: l10n.emptyCanvasTitle,
      subtitle: l10n.emptyCanvasSubtitle,
      versionLabel: version == null ? null : l10n.emptyCanvasVersion(version),
      recentFilesSection: CruxRecentListSection(
        list: recentProjects,
        strings: CruxRecentListStrings.of(context, CruxRecentKind.projects),
        icon: Icons.folder_outlined,
        onOpen: opening(recentProjects, onPickRecentProject),
      ),
      recentWorkspacesSection: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          CruxRecentListSection(
            list: recentSources,
            strings: CruxRecentListStrings.of(context, CruxRecentKind.files),
            onOpen: opening(recentSources, onPickRecentSourceFile),
          ),
          if (hasWorkspaces) ...[
            const SizedBox(height: 16),
            CruxRecentListSection(
              list: recentWorkspaces,
              strings: CruxRecentListStrings.of(
                context,
                CruxRecentKind.workspaces,
              ),
              icon: Icons.workspaces_outline,
              onOpen: opening(recentWorkspaces, onPickRecentWorkspace),
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
