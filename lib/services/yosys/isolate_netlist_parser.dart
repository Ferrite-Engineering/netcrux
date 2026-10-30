// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:isolate';

import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/yosys/black_box_port_inference.dart';
import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// Parses `yosys write_json` output into a [NetlistModel] on a **background
/// isolate**, so the multi-second parse of a large design never blocks the
/// UI isolate.
///
/// The repo's own performance report measures 0.34 s at 100 K cells and
/// 4.8 s at 1 M cells for [StreamingYosysJsonReader.parse]; run on the main
/// isolate inside a provider `build()` that is a hard UI freeze. This mirrors
/// the layout phase, which already solves on a spawned isolate.
///
/// **Result transfer is zero-copy.** The worker sends its final result with
/// [Isolate.exit], which hands the object graph to the receiving isolate
/// without the usual deep copy — so returning a million-cell [NetlistModel]
/// costs a pointer move, not a re-serialization on the UI thread. The model
/// is pure-Dart domain data (strings + maps of cells/nets/ports), so it is
/// send-safe.
///
/// **Cancellation.** [cancelSignal] (the provider's dispose completer) hard-
/// kills the worker isolate. [StreamingYosysJsonReader.parse] is a tight
/// *synchronous* loop, so the worker's event loop never turns mid-parse and
/// cooperative token checks cannot fire — an immediate [Isolate.kill] is the
/// only effective cancellation. On cancel the returned future completes with
/// `null` (the disposed provider ignores it anyway).
///
/// Throws [YosysJsonParseException] on malformed input, matching
/// [StreamingYosysJsonReader.parse] so the existing provider `catch` is
/// unchanged.
Future<NetlistModel?> parseNetlistOnIsolate(
  String rawJson, {
  Future<void>? cancelSignal,
}) async {
  final parsed = await _parseOnIsolate(
    rawJson,
    inferBlackBoxes: false,
    cancelSignal: cancelSignal,
  );
  return parsed?.model;
}

/// [parseNetlistOnIsolate] followed, on the same background isolate, by
/// [inferBlackBoxPorts]: for a netlist Yosys elaborated with undefined
/// modules left in as black boxes. Returns the model with every black-box
/// pin given a direction, and the report of what was inferred; `null` when
/// [cancelSignal] fires first.
Future<({NetlistModel model, BlackBoxReport report})?>
parseNetlistWithBlackBoxesOnIsolate(
  String rawJson, {
  Future<void>? cancelSignal,
}) => _parseOnIsolate(
  rawJson,
  inferBlackBoxes: true,
  cancelSignal: cancelSignal,
);

/// [parseNetlistOnIsolate] for a document that is a file: the worker reads
/// [path] itself, in fixed-size chunks (`ChunkedYosysJsonReader`), so the
/// document is never a string or a buffer, in either isolate, and its size
/// is not limited. This is the entry point for anything that can be large.
///
/// Throws [YosysJsonParseException] as [parseNetlistOnIsolate] does.
Future<NetlistModel?> parseNetlistFileOnIsolate(
  String path, {
  Future<void>? cancelSignal,
}) async {
  final parsed = await _parseOnIsolate(
    _NetlistFile(path),
    inferBlackBoxes: false,
    cancelSignal: cancelSignal,
  );
  return parsed?.model;
}

/// [parseNetlistWithBlackBoxesOnIsolate] for a document that is a file; see
/// [parseNetlistFileOnIsolate].
Future<({NetlistModel model, BlackBoxReport report})?>
parseNetlistFileWithBlackBoxesOnIsolate(
  String path, {
  Future<void>? cancelSignal,
}) => _parseOnIsolate(
  _NetlistFile(path),
  inferBlackBoxes: true,
  cancelSignal: cancelSignal,
);

/// Marks the document handed to the worker as a path to read rather than
/// the text itself.
class _NetlistFile {
  const _NetlistFile(this.path);

  final String path;
}

Future<({NetlistModel model, BlackBoxReport report})?> _parseOnIsolate(
  Object rawJson, {
  required bool inferBlackBoxes,
  Future<void>? cancelSignal,
}) async {
  // A single port receives the result (via Isolate.exit), plus any onExit
  // (`null`) and onError (`[error, stack]`) notifications. Routing all three
  // through one port makes their order well-defined (FIFO): the Isolate.exit
  // payload is always enqueued before the onExit `null`, so a normal result
  // is never mistaken for a premature exit.
  final port = ReceivePort();

  final Isolate isolate;
  try {
    isolate = await Isolate.spawn<List<Object?>>(
      _parseEntry,
      <Object?>[
        // A path travels as its string and is read in the worker.
        if (rawJson is _NetlistFile) rawJson.path else rawJson,
        port.sendPort,
        inferBlackBoxes,
        rawJson is _NetlistFile,
      ],
      debugName: 'netlist-parse',
      onExit: port.sendPort,
      onError: port.sendPort,
    );
  } on Object {
    port.close();
    rethrow;
  }

  final completer = Completer<({NetlistModel model, BlackBoxReport report})?>();
  var settled = false;

  final sub = port.listen((message) {
    if (settled) return;
    settled = true;
    if (message is List && message.length == 3 && message[0] is bool) {
      // Our protocol: [true, NetlistModel, BlackBoxReport] or
      // [false, errorMessage, null].
      if (message[0] == true) {
        completer.complete((
          model: message[1]! as NetlistModel,
          report: message[2]! as BlackBoxReport,
        ));
      } else {
        completer.completeError(YosysJsonParseException(message[1]! as String));
      }
    } else if (message is List) {
      // onError delivers [errorString, stackTraceString].
      completer.completeError(
        YosysJsonParseException(
          'Yosys JSON parse isolate crashed: ${message.first}',
        ),
      );
    } else {
      // onExit with no prior result (message == null) — the worker died
      // without returning (e.g. OOM). Surface it rather than hang.
      completer.completeError(
        const YosysJsonParseException(
          'Yosys JSON parse isolate exited before returning a result',
        ),
      );
    }
  });

  StreamSubscription<void>? cancelSub;
  final cancel = cancelSignal;
  if (cancel != null) {
    cancelSub = cancel.asStream().listen((_) {
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

/// Worker entry point. Runs on the spawned isolate and returns its result
/// via [Isolate.exit] for a zero-copy handoff.
void _parseEntry(List<Object?> args) {
  final source = args[0]! as String;
  final reply = args[1]! as SendPort;
  final inferBlackBoxes = args[2]! as bool;
  final isFile = args[3]! as bool;
  try {
    final model = isFile
        ? ChunkedYosysJsonReader.parseFile(source)
        : const StreamingYosysJsonReader().parse(source);
    if (!inferBlackBoxes) {
      Isolate.exit(reply, <Object?>[true, model, BlackBoxReport.none]);
    }
    final inferred = inferBlackBoxPorts(model);
    Isolate.exit(reply, <Object?>[true, inferred.model, inferred.report]);
  } on YosysJsonParseException catch (e) {
    Isolate.exit(reply, <Object?>[false, e.message, null]);
  } on Object catch (e) {
    Isolate.exit(reply, <Object?>[
      false,
      'Yosys JSON could not be parsed: $e',
      null,
    ]);
  }
}
