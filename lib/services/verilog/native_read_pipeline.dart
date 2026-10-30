// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_stub_service.dart';
import 'package:netcrux/services/verilog/native_netlist_reader.dart';

/// Why the native gate-level reader does not apply to [project] at all, in
/// words for Diagnostics, or `null` when it may be tried.
///
/// It reads Verilog only; a project that asks Yosys to run extra commands or
/// to lower the design (`lowerToStructural`, `extraYosysCommands`) asked for
/// Yosys's result, which the native reader does not produce.
String? nativeReaderInapplicableReason(NetcruxProject project) {
  if (project.sourceFiles.isEmpty) return 'the project has no source files';
  if (project.extraYosysCommands.isNotEmpty) {
    return 'the project runs extra Yosys commands';
  }
  if (project.lowerToStructural) {
    return 'the project lowers the design with Yosys';
  }
  for (final path in project.sourceFiles) {
    if (project.resolveLanguage(path) != NetcruxSourceLanguage.verilog) {
      return 'it reads Verilog netlists only (${_name(path)} is not Verilog)';
    }
  }
  return null;
}

String _name(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

/// The result of trying the native reader on a project.
@immutable
sealed class NativeAttempt {
  const NativeAttempt();
}

/// The design was read.
class NativeAttemptRead extends NativeAttempt {
  /// Creates the result.
  const NativeAttemptRead(this.success, {required this.libraryWarnings});

  /// The model and what was read.
  final NativeReadSuccess success;

  /// Warnings from reading the Liberty libraries, for Diagnostics.
  final List<String> libraryWarnings;

  /// The Diagnostics lines for a successful read: the information line
  /// naming the reader, then the library, model and reader warnings, then
  /// the black-box report's.
  List<String> get diagnosticLines => <String>[
    nativeReadInfoLine(success.stats),
    ...libraryWarnings,
    ...success.warnings,
    ...success.report.warningLines,
  ];
}

/// The reader declined; Yosys should read the design.
class NativeAttemptDeclined extends NativeAttempt {
  /// Creates the result.
  const NativeAttemptDeclined(this.outcome, {required this.libraryWarnings});

  /// Why and where.
  final NativeReadFallbackOutcome outcome;

  /// Warnings from reading the Liberty libraries.
  final List<String> libraryWarnings;
}

/// The read was cancelled (the tab closed or the project changed).
class NativeAttemptCancelled extends NativeAttempt {
  /// Creates the result.
  const NativeAttemptCancelled();
}

/// `Info:` line saying the native reader read the design, with its size.
String nativeReadInfoLine(NativeReadStats stats) {
  final seconds = (stats.readMilliseconds / 1000).toStringAsFixed(1);
  final modules = stats.modules == 1 ? 'module' : 'modules';
  final cells = stats.cells == 1 ? 'cell' : 'cells';
  return 'Info: Netlist read by the native gate-level reader (beta): '
      '${stats.modules} $modules, ${stats.cells} $cells, top module '
      '${stats.topModule}, $seconds s. Yosys was not run.';
}

/// `Info:` line saying Yosys reads the design, and [why] it is not the
/// native reader.
String yosysReadInfoLine(String why) => 'Info: Netlist read by Yosys ($why).';

/// Tries the native reader on [project]: Liberty libraries through
/// [liberty], then the worker isolate. [cancelSignal] stops it.
Future<NativeAttempt> attemptNativeRead(
  NetcruxProject project,
  LibertyStubService liberty, {
  Future<void>? cancelSignal,
}) async {
  var libraries = const <LibertyLibrary>[];
  var libraryWarnings = const <String>[];
  if (project.libertyFiles.isNotEmpty) {
    final loaded = await liberty.librariesFor(project.libertyFiles);
    libraries = loaded.libraries;
    libraryWarnings = <String>[
      for (final warning in loaded.warnings) 'Warning: $warning',
    ];
  }
  final outcome = await readGateLevelNetlistOnIsolate(
    NativeReadRequest(
      sourceFiles: project.sourceFiles,
      libertyLibraries: libraries,
      cellModelFiles: project.cellModelFiles,
      topModule: project.topModule,
    ),
    cancelSignal: cancelSignal,
  );
  return switch (outcome) {
    null => const NativeAttemptCancelled(),
    final NativeReadSuccess success => NativeAttemptRead(
      success,
      libraryWarnings: libraryWarnings,
    ),
    final NativeReadFallbackOutcome declined => NativeAttemptDeclined(
      declined,
      libraryWarnings: libraryWarnings,
    ),
  };
}
