// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// file_picker's dialogs on Linux, drawn by the runner with GTK.
///
/// file_picker's own Linux code asks the XDG desktop portal to draw every
/// dialog, over the DBus session bus. A Linux host displayed remotely (ssh X
/// forwarding, VNC, ETX, a farm job started from another host) often has no
/// reachable session bus, and then every Open, Save and Export fails with a
/// `SocketException`. Where a bus is reachable it can belong to the desktop
/// of the machine's console, which puts the dialog on that screen instead.
///
/// The runner's `netcrux/file_dialog` channel (`linux/runner/
/// remote_display.cc`) shows a GTK file chooser in the app's own process, on
/// the display its window is on, and needs no desktop service.
class GtkFilePicker extends FilePickerPlatform {
  /// Creates a picker that talks to the runner over [_channel].
  GtkFilePicker([this._channel = const MethodChannel('netcrux/file_dialog')]);

  final MethodChannel _channel;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    final paths = await _show('open', <String, Object?>{
      'title': dialogTitle,
      'folder': initialDirectory,
      'multiple': allowMultiple,
      'extensions': _extensions(type, allowedExtensions),
    });
    if (paths.isEmpty) return null;
    return FilePickerResult(<PlatformFile>[
      for (final path in paths) await _platformFile(path, withData: withData),
    ]);
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    final paths = await _show('directory', <String, Object?>{
      'title': dialogTitle,
      'folder': initialDirectory,
    });
    return paths.firstOrNull;
  }

  /// Writes [bytes] to the chosen path when there are any, as file_picker
  /// does. Callers that write the file themselves pass none.
  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    bool lockParentWindow = false,
  }) async {
    final paths = await _show('save', <String, Object?>{
      'title': dialogTitle,
      'folder': initialDirectory,
      'name': fileName,
      'extensions': _extensions(type, allowedExtensions),
    });
    final path = paths.firstOrNull;
    if (path != null && bytes.isNotEmpty) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  }

  Future<List<String>> _show(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final paths = await _channel.invokeListMethod<String>(method, arguments);
    return paths ?? const <String>[];
  }

  /// NetCrux filters only by explicit extensions; any other [type] shows
  /// every file.
  static List<String>? _extensions(FileType type, List<String>? extensions) =>
      type == FileType.custom ? extensions : null;

  static Future<PlatformFile> _platformFile(
    String path, {
    required bool withData,
  }) async {
    final file = File(path);
    return PlatformFile(
      path: path,
      name: p.basename(path),
      size: await file.length(),
      bytes: withData ? await file.readAsBytes() : null,
    );
  }
}

/// Makes file_picker use [GtkFilePicker] on Linux. Does nothing on any other
/// platform, the web included.
void useGtkFileDialogsOnLinux() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) return;
  FilePickerPlatform.instance = GtkFilePicker();
}
