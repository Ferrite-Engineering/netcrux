// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/interfaces/elaboration_timeout_policy.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';

/// The Yosys run that elaborates [project]: the one request the app's
/// elaboration pipeline and the headless `netcrux` command line both send.
///
/// Defines follow the Verilator and Yosys convention: an empty value is
/// `NAME`, any other `NAME=VALUE`. Each source's language is
/// [NetcruxProject.resolveLanguage]'s. [libertyStubPath], when given, is the
/// generated black-box stub file for the project's cell libraries, read
/// first as plain Verilog, so a module the sources define under a cell's
/// name replaces the stub (Yosys replaces a black box with a later full
/// definition). The lowering passes run before the project's own extra
/// commands, so a `flatten` or `opt_clean` of the user's works on gates and
/// flip-flops, not on processes.
YosysRunRequest elaborationRequestFor(
  NetcruxProject project, {
  String? libertyStubPath,
}) {
  return YosysRunRequest(
    sources: <YosysSourceFile>[
      if (libertyStubPath != null) YosysSourceFile(libertyStubPath),
      for (final path in project.sourceFiles)
        _sourceFileFor(path, project.resolveLanguage(path)),
    ],
    topModule: project.topModule.isEmpty ? null : project.topModule,
    defines: <String>[
      for (final entry in project.defines.entries)
        if (entry.value.isEmpty) entry.key else '${entry.key}=${entry.value}',
    ],
    includePaths: project.includePaths,
    extraCommands: <String>[
      if (project.lowerToStructural) ...kLowerToStructuralCommands,
      ...project.extraYosysCommands,
    ],
    vhdlTopUnit: project.topModule.isEmpty ? null : project.topModule,
    allowUndefinedModules: project.blackBoxMissingModules,
  );
}

YosysSourceFile _sourceFileFor(String path, NetcruxSourceLanguage lang) {
  switch (lang) {
    case NetcruxSourceLanguage.verilog:
      return YosysSourceFile(path);
    case NetcruxSourceLanguage.systemVerilog:
      return YosysSourceFile.systemVerilog(path);
    case NetcruxSourceLanguage.vhdl:
      return YosysSourceFile.vhdl(path);
    case NetcruxSourceLanguage.auto:
      // `auto` is resolved upstream by `resolveLanguage`; reaching here means
      // the inference returned `auto`, which is not a runtime value. Read as
      // Verilog, as before.
      return YosysSourceFile(path);
  }
}

/// The size signal the elaboration time budget is computed from: the
/// number of [project]'s sources and their combined size in bytes. A source
/// that cannot be read counts 0 bytes; the policy's floor still bounds the
/// run.
Future<ElaborationSizeEstimate> elaborationSizeOf(
  NetcruxProject project,
) async {
  var totalBytes = 0;
  for (final path in project.sourceFiles) {
    try {
      // Off the calling isolate's event loop on purpose: the app calls this
      // from a provider's build().
      // ignore: avoid_slow_async_io
      final stat = await File(path).stat();
      // A missing path has size -1; it counts as 0, not as a negative.
      if (stat.size > 0) totalBytes += stat.size;
    } on FileSystemException {
      // Unreadable: counts as 0 bytes.
    }
  }
  return ElaborationSizeEstimate(
    sourceFileCount: project.sourceFiles.length,
    totalSourceBytes: totalBytes,
  );
}
