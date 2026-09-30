// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:crux_project/crux_project.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Result of a file-open dialog. Either at least one path was selected or
/// the user cancelled (the picker returned `null`). Distinguished here so
/// callers can disambiguate "cancelled" from "no files selected".
class FileOpenResult {
  /// Creates a result containing [paths]. Use [FileOpenResult.cancelled]
  /// for the user-cancelled case.
  const FileOpenResult(this.paths);

  /// The user-cancelled case — equivalent to `paths.isEmpty`, but kept
  /// distinct so callers can decide whether to surface a snackbar etc.
  const FileOpenResult.cancelled() : paths = const [];

  /// Absolute paths picked by the user, in display order. Empty when the
  /// user cancelled.
  final List<String> paths;

  /// True when the user cancelled the picker (no paths returned).
  bool get isCancelled => paths.isEmpty;
}

/// Wraps the `file_picker` plugin behind a service so screens and providers
/// don't depend on it directly. file_picker 12's API is static (the
/// instance-based `FilePicker.platform` seam was removed), so this service is
/// the single open-core indirection point for the picker.
class FileOpenService {
  /// Creates a service.
  FileOpenService();

  /// Prompts the user for a project file. Accepts the working
  /// `.netcrux-project` project format, the per-tab `.netcrux` session export
  /// format and the suite's `<design>.crux-project` manifest — the welcome
  /// screen's `_openProjectByPath` branches on the name. Returns the picked
  /// path or [FileOpenResult.cancelled].
  Future<FileOpenResult> pickProject({required String dialogTitle}) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const <String>[
        'netcrux-project',
        'netcrux',
        kCruxProjectExtension,
      ],
    );
    if (result == null || result.files.isEmpty) {
      return const FileOpenResult.cancelled();
    }
    final paths = <String>[
      for (final file in result.files)
        if (file.path != null) file.path!,
    ];
    return FileOpenResult(paths);
  }

  /// Prompts the user for a Vivado-style `.f` filelist. Used by the
  /// `File → Import → Vivado Filelist…` action.
  Future<FileOpenResult> pickFilelist({required String dialogTitle}) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const <String>['f'],
    );
    if (result == null || result.files.isEmpty) {
      return const FileOpenResult.cancelled();
    }
    final paths = <String>[
      for (final file in result.files)
        if (file.path != null) file.path!,
    ];
    return FileOpenResult(paths);
  }

  /// Prompts the user for one or more Verilog / VHDL source files. Returns
  /// the picked paths or [FileOpenResult.cancelled].
  Future<FileOpenResult> pickSourceFiles({required String dialogTitle}) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      // file_picker 12's pickFiles selects multiple by default; the removed
      // `allowMultiple: true` is now redundant.
      allowedExtensions: const [
        'v',
        'sv',
        'svh',
        'vh',
        'vhd',
        'vhdl',
      ],
    );
    if (result == null || result.files.isEmpty) {
      return const FileOpenResult.cancelled();
    }
    final paths = <String>[
      for (final file in result.files)
        if (file.path != null) file.path!,
    ];
    return FileOpenResult(paths);
  }

  /// Prompts the user for a design given as files: one or more Verilog /
  /// VHDL sources, or a single pre-built Yosys JSON netlist. Returns the
  /// picked paths or [FileOpenResult.cancelled]. Used where either form of a
  /// design will do, such as the comparison side of a netlist diff.
  Future<FileOpenResult> pickDesignFiles({required String dialogTitle}) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const [
        'v',
        'sv',
        'svh',
        'vh',
        'vhd',
        'vhdl',
        'json',
      ],
    );
    if (result == null || result.files.isEmpty) {
      return const FileOpenResult.cancelled();
    }
    final paths = <String>[
      for (final file in result.files)
        if (file.path != null) file.path!,
    ];
    return FileOpenResult(paths);
  }

  /// Prompts the user for a pre-built Yosys JSON netlist and returns where
  /// the pipeline can read it, or [FileOpenResult.cancelled].
  ///
  /// On desktop that is the file's path. The browser has no paths: the picker
  /// hands back a `blob:` URL the netlist loader fetches, and the file's own
  /// name rides on it as the URL fragment — ignored when the blob is fetched,
  /// but what the tab and status bar show instead of the blob's opaque id
  /// (see `NetcruxProject.locationLabel`).
  Future<FileOpenResult> pickNetlistJson({required String dialogTitle}) async {
    final file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    final path = file?.path;
    if (file == null || path == null) return const FileOpenResult.cancelled();
    return FileOpenResult(<String>[
      if (kIsWeb) '$path#${Uri.encodeComponent(file.name)}' else path,
    ]);
  }

  /// Prompts the user for a VCD waveform — the simulation dump switching
  /// activity is measured from. Returns the picked path or
  /// [FileOpenResult.cancelled].
  Future<FileOpenResult> pickWaveformFile({required String dialogTitle}) async {
    final file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const <String>['vcd'],
    );
    final path = file?.path;
    if (path == null) return const FileOpenResult.cancelled();
    return FileOpenResult(<String>[path]);
  }

  /// Prompts the user for a `.netcrux-workspace` named workspace file.
  /// Returns the picked path or [FileOpenResult.cancelled].
  Future<FileOpenResult> pickWorkspace({required String dialogTitle}) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const <String>['netcrux-workspace'],
    );
    if (result == null || result.files.isEmpty) {
      return const FileOpenResult.cancelled();
    }
    final paths = <String>[
      for (final file in result.files)
        if (file.path != null) file.path!,
    ];
    return FileOpenResult(paths);
  }

  /// Prompts the user for a destination path for a `.netcrux-workspace`
  /// file. Returns the chosen absolute path or `null` if the user
  /// cancelled.
  Future<String?> pickWorkspaceSaveAs({
    required String dialogTitle,
    String? defaultFileName,
  }) {
    return FilePicker.saveFile(
      // file_picker 12 requires bytes & writes the file; pass empty so it
      // only returns the chosen path and the workspace codec writes it.
      bytes: Uint8List(0),
      dialogTitle: dialogTitle,
      fileName: defaultFileName ?? 'workspace.netcrux-workspace',
      type: FileType.custom,
      allowedExtensions: const <String>['netcrux-workspace'],
    );
  }
}
