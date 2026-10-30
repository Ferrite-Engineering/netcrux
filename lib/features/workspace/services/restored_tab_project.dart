// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/enums/netcrux_design_source.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/services/filelist/filelist_reader.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:path/path.dart' as p;

/// Whether [path] ends in `.<extension>`, ignoring case.
bool hasFileSuffix(String path, String extension) =>
    path.toLowerCase().endsWith('.$extension');

/// Reads a `.netcrux-project` file with its relative paths anchored to the
/// project's own directory: a committed project file carries relative paths
/// so it can travel between checkouts.
Future<NetcruxProject> readNetcruxProjectFile(String path) async {
  final project = await const NetcruxProjectFileReader().read(path);
  return resolveProjectPaths(project, p.dirname(path));
}

/// The project and entry route a restored tab is rebuilt from, or `null` when
/// its [payload] names no sources.
///
/// A tab opened from a `.netcrux-project` or a `.f` filelist is re-read from
/// that file: the payload carries only its sources and top module, and
/// rebuilding the project from those silently dropped its defines, include
/// paths, extra Yosys commands and lowering, so the restored tab elaborated a
/// different design. When the file cannot be read any more, the payload is the
/// best there is. Cell libraries and the black-box option the tab set itself
/// (see [NetcruxTabPayload.libertyFiles]) apply over whatever the file says.
Future<({NetcruxProject project, NetcruxDesignSource source})?>
restoredTabProject(NetcruxTabPayload payload) async {
  final projectFile = payload.projectFilePath;
  final isProjectFile =
      projectFile != null &&
      hasFileSuffix(projectFile, kNetcruxProjectExtension);
  final isFilelist =
      projectFile != null && hasFileSuffix(projectFile, kFilelistExtension);
  final libertyOverride = payload.libertyFiles;
  final blackBoxOverride = payload.blackBoxMissingModules;
  if (isProjectFile || isFilelist) {
    try {
      final fromFile = isFilelist
          ? await const FilelistReader().readAsProject(projectFile)
          : await readNetcruxProjectFile(projectFile);
      return (
        project: fromFile.copyWith(
          libertyFiles: libertyOverride,
          blackBoxMissingModules: blackBoxOverride,
        ),
        source: isFilelist
            ? NetcruxDesignSource.filelist
            : NetcruxDesignSource.project,
      );
    } on Object {
      // Unreadable now: fall through to the payload.
    }
  }
  if (payload.sourceFiles.isEmpty) return null;
  return (
    project: NetcruxProject.create(
      sourceFiles: payload.sourceFiles,
      topModule: payload.topModule,
      libertyFiles: libertyOverride ?? const <String>[],
      blackBoxMissingModules: blackBoxOverride ?? false,
    ),
    source: projectFile == null
        ? NetcruxDesignSource.rtl
        : NetcruxDesignSource.project,
  );
}

/// Gives the tab behind [container] the design its [payload] names, when the
/// tab has none yet.
///
/// A tab's project lives in its own container, not in the saved workspace, so
/// a tab restored from `workspace.json` starts with the empty project until
/// something pushes its sources in. This is that push, and it leaves a tab
/// that already holds a design alone: a launch argument or an open that got
/// there first has installed the project it means, and replacing it would
/// start a second read of a design that can take minutes to load.
///
/// [isCurrent] is asked again after the project file has been read, and the
/// push is dropped when it answers `false` (the tab was closed, or the screen
/// went away, in the meantime). Returns whether a project was installed.
Future<bool> hydrateTabProject(
  ProviderContainer container,
  NetcruxTabPayload payload, {
  bool Function()? isCurrent,
}) async {
  if (container.read(currentProjectProvider).sourceFiles.isNotEmpty) {
    return false;
  }
  final restored = await restoredTabProject(payload);
  if (restored == null) return false;
  if (isCurrent != null && !isCurrent()) return false;
  // Re-checked after the await: an open that landed while the project file
  // was being read has already installed the design it means.
  if (container.read(currentProjectProvider).sourceFiles.isNotEmpty) {
    return false;
  }
  container
      .read(currentProjectProvider.notifier)
      .setProject(restored.project, source: restored.source);
  return true;
}
