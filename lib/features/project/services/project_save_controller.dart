// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:path/path.dart' as p;

/// Writes the active tab's project as a `.netcrux-project` file: the Save
/// Project As… half of the project format, whose Open half is the workspace
/// screen's open-by-path route.
///
/// The project a tab elaborates with is the same whether it came from a
/// project file, a filelist import or sources opened one by one, so any tab
/// can be saved as a project, and a filelist's defines and include paths
/// gain a file NetCrux itself writes.
///
/// Reads through a raw [ProviderContainer], the tab's, so the workspace
/// dispatcher hands in the active tab exactly as it does for the session
/// controller.
class ProjectSaveController {
  /// Creates a controller over [container], the tab whose project is saved.
  const ProjectSaveController({
    required this.container,
    required this.context,
    required this.l10n,
  });

  /// The tab container; its `currentProjectProvider` is what gets written.
  final ProviderContainer container;

  /// Where the success and failure toasts are shown. Checked for `mounted`
  /// before each one, since a save outlives the picker's await.
  final BuildContext context;

  /// Localized strings.
  final L10N l10n;

  /// Asks the user where to write, then writes.
  ///
  /// Returns the path written, or `null` when the picker was cancelled or
  /// the write failed. Both already explain themselves through a toast;
  /// the caller needs the outcome because it records the file as the tab's
  /// project file, as a recent project and in the audit log, and each of
  /// those must follow a write that happened.
  Future<String?> saveAs() async {
    final project = container.read(currentProjectProvider);
    final path = await FilePicker.saveFile(
      // file_picker 12 requires bytes & writes the file; pass empty so it
      // only returns the chosen path and the project is written here.
      bytes: Uint8List(0),
      dialogTitle: l10n.projectSaveDialogTitle,
      fileName: suggestedFileName(project),
      lockParentWindow: true,
    );
    if (path == null) return null;
    final target = withProjectExtension(path);
    return await saveToPath(target) ? target : null;
  }

  /// Writes the tab's project to [path] with no dialog, the picker-free
  /// counterpart to [saveAs] that tests drive directly.
  ///
  /// Source and include paths go in relative to the file's directory where
  /// they share a root with it ([relativizeProjectPaths]), so a committed
  /// project opens from another checkout; the write is atomic
  /// ([NetcruxProjectFileWriter]). Returns whether it succeeded.
  Future<bool> saveToPath(String path) async {
    try {
      final project = container.read(currentProjectProvider);
      final portable = relativizeProjectPaths(project, p.dirname(path));
      await const NetcruxProjectFileWriter().write(path, portable);
      if (context.mounted) {
        showCruxInfoSnack(context, l10n.exportSuccessMessage(path));
      }
      return true;
    } on Object catch (e) {
      if (context.mounted) {
        showCruxErrorSnack(context, l10n.projectSaveFailed(e.toString()));
      }
      return false;
    }
  }

  /// The file name the save dialog offers for [project]: the top module when
  /// one is set, else the first source's stem, else `design`, with the
  /// project extension.
  static String suggestedFileName(NetcruxProject project) {
    final String stem;
    if (project.topModule.isNotEmpty) {
      stem = project.topModule;
    } else if (project.sourceFiles.isNotEmpty) {
      stem = p.basenameWithoutExtension(project.sourceFiles.first);
    } else {
      stem = 'design';
    }
    return '$stem.$kNetcruxProjectExtension';
  }

  /// [path] with the project extension appended when it lacks one. The
  /// open-by-path route recognises a project by its extension, so a project
  /// saved under another name would reopen as an HDL source.
  static String withProjectExtension(String path) =>
      path.toLowerCase().endsWith('.$kNetcruxProjectExtension')
      ? path
      : '$path.$kNetcruxProjectExtension';
}
