// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/verilog/cell_interface.dart';
import 'package:netcrux/services/verilog/gate_level_model_builder.dart';
import 'package:netcrux/services/verilog/gate_level_parser.dart';
import 'package:netcrux/services/verilog/verilog_byte_source.dart';
import 'package:netcrux/services/verilog/verilog_cell_model_reader.dart';
import 'package:netcrux/services/verilog/verilog_scanner.dart';
import 'package:netcrux/services/yosys/black_box_port_inference.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

/// What the native gate-level reader is asked to read.
@immutable
class NativeReadRequest {
  /// Creates a request.
  const NativeReadRequest({
    required this.sourceFiles,
    this.libertyLibraries = const <LibertyLibrary>[],
    this.cellModelFiles = const <String>[],
    this.topModule = '',
    this.bufferSize = VerilogScanner.defaultBufferSize,
    this.maxTokenBytes = 64 * 1024,
  });

  /// The Verilog sources, in order; `.v` or `.v.gz`.
  final List<String> sourceFiles;

  /// Cell libraries already parsed, in the project's order.
  final List<LibertyLibrary> libertyLibraries;

  /// Verilog cell model files whose module headers give pin directions.
  final List<String> cellModelFiles;

  /// The top module, or empty to infer it as `hierarchy -auto-top` does.
  final String topModule;

  /// The scanner's read buffer size, in bytes.
  final int bufferSize;

  /// The longest identifier, number or string accepted, in bytes.
  final int maxTokenBytes;
}

/// What a read produced.
sealed class NativeReadOutcome {
  const NativeReadOutcome();
}

/// The file was read: the model, with black-box pins given directions.
class NativeReadSuccess extends NativeReadOutcome {
  /// Creates the outcome.
  const NativeReadSuccess({
    required this.model,
    required this.report,
    required this.warnings,
    required this.stats,
  });

  /// The model, shaped like the Yosys route's.
  final NetlistModel model;

  /// The black boxes and undeclared pins found, as the Yosys route reports.
  final BlackBoxReport report;

  /// `Warning:` lines for Diagnostics, in order (library and model-file
  /// notes first, then the reader's own, not including [report]'s).
  final List<String> warnings;

  /// What was read.
  final NativeReadStats stats;
}

/// Counts and timings of a native read.
@immutable
class NativeReadStats {
  /// Creates the stats.
  const NativeReadStats({
    required this.modules,
    required this.cells,
    required this.nets,
    required this.topModule,
    required this.files,
    required this.libertyCells,
    required this.modelCells,
    required this.readMilliseconds,
  });

  /// Modules in the model, black-box stubs included.
  final int modules;

  /// Cells in all modules.
  final int cells;

  /// Declared nets in all modules.
  final int nets;

  /// The top module's name.
  final String topModule;

  /// Source files read.
  final int files;

  /// Cell interfaces taken from Liberty libraries.
  final int libertyCells;

  /// Cell interfaces taken from cell model files.
  final int modelCells;

  /// Wall time of the read, in milliseconds.
  final int readMilliseconds;
}

/// The reader declined: the Yosys route should read the design.
class NativeReadFallbackOutcome extends NativeReadOutcome {
  /// Creates the outcome.
  const NativeReadFallbackOutcome({
    required this.stop,
    required this.message,
    required this.path,
    required this.line,
  });

  /// The class of reason.
  final NativeReaderStop stop;

  /// The construct or problem, in English, for Diagnostics.
  final String message;

  /// The file it was found in, or empty.
  final String path;

  /// The 1-based line, or `0`.
  final int line;

  /// The Diagnostics line, `path:line: Warning: ...`, naming the construct
  /// and where it is and saying Yosys reads the design instead.
  String get diagnosticLine {
    final where = path.isEmpty ? '' : (line > 0 ? '$path:$line: ' : '$path: ');
    final what = switch (stop) {
      NativeReaderStop.unsupported => 'uses $message, which it does not read',
      NativeReaderStop.malformed => 'could not read this file ($message)',
      NativeReaderStop.inconsistent => 'found a problem ($message)',
    };
    return '${where}Warning: The native gate-level reader $what; '
        'Yosys reads this design instead.';
  }
}

/// Reads the structural Verilog in [request] into a model.
///
/// Synchronous and CPU-bound: it belongs on a worker isolate
/// ([readGateLevelNetlistOnIsolate]). Returns [NativeReadFallbackOutcome]
/// for anything it cannot read faithfully, and `null` when [cancellation]
/// fires.
NativeReadOutcome? readGateLevelNetlist(
  NativeReadRequest request, {
  CancellationToken? cancellation,
}) {
  final clock = Stopwatch()..start();
  try {
    final interfaces = CellInterfaces();
    request.libertyLibraries.forEach(interfaces.addLiberty);
    final warnings = <String>[];
    for (final path in request.cellModelFiles) {
      try {
        final file = readCellModelFile(
          path,
          cancellation: cancellation,
          bufferSize: request.bufferSize,
          maxTokenBytes: request.maxTokenBytes,
        );
        interfaces.addModels(path, file.cells);
        warnings.addAll(
          file.warnings.map((w) => 'Warning: $w'),
        );
      } on VerilogSourceException catch (e) {
        warnings.add(
          '${e.path}: Warning: cell model file skipped: ${e.message}',
        );
      } on NativeReaderFallback catch (e) {
        warnings.add(
          '${e.path}:${e.line}: Warning: cell model file skipped: ${e.message}',
        );
      }
    }
    warnings.addAll(interfaces.warnings.map((w) => 'Warning: $w'));
    if (cancellation?.isCancelled ?? false) return null;

    final parser = GateLevelParser(
      cancellation: cancellation,
      bufferSize: request.bufferSize,
      maxTokenBytes: request.maxTokenBytes,
    );
    for (final path in request.sourceFiles) {
      parser.parseFile(path);
      if (cancellation?.isCancelled ?? false) return null;
    }
    final (model, report) = GateLevelModelBuilder(
      parser.design,
      interfaces,
      cancellation: cancellation,
    ).build(topName: request.topModule);
    if (cancellation?.isCancelled ?? false) return null;
    warnings.addAll(report.warnings);
    final inferred = inferBlackBoxPorts(model);
    clock.stop();
    return NativeReadSuccess(
      model: inferred.model,
      report: inferred.report,
      warnings: warnings,
      stats: NativeReadStats(
        modules: report.modules,
        cells: report.cells,
        nets: report.nets,
        topModule: report.topModule,
        files: request.sourceFiles.length,
        libertyCells: interfaces.libertyCount,
        modelCells: interfaces.modelCount,
        readMilliseconds: clock.elapsedMilliseconds,
      ),
    );
  } on NativeReaderFallback catch (e) {
    return NativeReadFallbackOutcome(
      stop: e.stop,
      message: e.message,
      path: e.path,
      line: e.line,
    );
  } on VerilogSourceException catch (e) {
    return NativeReadFallbackOutcome(
      stop: NativeReaderStop.malformed,
      message: e.message,
      path: e.path,
      line: 0,
    );
  } on Object catch (e) {
    if (isGateLevelCancellation(e)) return null;
    return NativeReadFallbackOutcome(
      stop: NativeReaderStop.malformed,
      message: 'an internal error: $e',
      path: request.sourceFiles.isEmpty ? '' : request.sourceFiles.first,
      line: 0,
    );
  }
}

/// [readGateLevelNetlist] on a worker isolate, so a large netlist never
/// blocks the UI isolate. The model comes back by [Isolate.exit], without a
/// copy.
///
/// [cancelSignal] kills the worker, and the future completes with `null`. A
/// worker that dies without answering (out of memory, say) is reported as a
/// [NativeReadFallbackOutcome], so the design is still read by Yosys.
Future<NativeReadOutcome?> readGateLevelNetlistOnIsolate(
  NativeReadRequest request, {
  Future<void>? cancelSignal,
}) async {
  final port = ReceivePort();
  final Isolate isolate;
  try {
    isolate = await Isolate.spawn<List<Object?>>(
      _entry,
      <Object?>[request, port.sendPort],
      debugName: 'netlist-native-read',
      onExit: port.sendPort,
      onError: port.sendPort,
    );
  } on Object {
    port.close();
    rethrow;
  }
  final completer = Completer<NativeReadOutcome?>();
  var settled = false;
  final sub = port.listen((message) {
    if (settled) return;
    settled = true;
    if (message is NativeReadOutcome) {
      completer.complete(message);
    } else if (message is List) {
      completer.complete(
        NativeReadFallbackOutcome(
          stop: NativeReaderStop.malformed,
          message: 'the reader stopped unexpectedly: ${message.first}',
          path: '',
          line: 0,
        ),
      );
    } else {
      completer.complete(
        const NativeReadFallbackOutcome(
          stop: NativeReaderStop.malformed,
          message: 'the reader stopped before it finished',
          path: '',
          line: 0,
        ),
      );
    }
  });
  StreamSubscription<void>? cancelSub;
  if (cancelSignal != null) {
    cancelSub = cancelSignal.asStream().listen((_) {
      if (settled) return;
      settled = true;
      isolate.kill(priority: Isolate.immediate);
      completer.complete(null);
    });
  }
  try {
    return await completer.future;
  } finally {
    await sub.cancel();
    await cancelSub?.cancel();
    port.close();
  }
}

void _entry(List<Object?> args) {
  final request = args[0]! as NativeReadRequest;
  final reply = args[1]! as SendPort;
  final outcome = readGateLevelNetlist(request);
  Isolate.exit(
    reply,
    outcome ??
        const NativeReadFallbackOutcome(
          stop: NativeReaderStop.malformed,
          message: 'the read was cancelled',
          path: '',
          line: 0,
        ),
  );
}
