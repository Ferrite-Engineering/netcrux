// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:isolate';

import 'package:netcrux/domain/models/netlist/netlist_model.dart';
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
      <Object?>[rawJson, port.sendPort],
      debugName: 'netlist-parse',
      onExit: port.sendPort,
      onError: port.sendPort,
    );
  } on Object {
    port.close();
    rethrow;
  }

  final completer = Completer<NetlistModel?>();
  var settled = false;

  final sub = port.listen((message) {
    if (settled) return;
    settled = true;
    if (message is List && message.length == 2 && message[0] is bool) {
      // Our protocol: [true, NetlistModel] or [false, errorMessage].
      if (message[0] == true) {
        completer.complete(message[1] as NetlistModel?);
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
  final rawJson = args[0]! as String;
  final reply = args[1]! as SendPort;
  try {
    final model = const StreamingYosysJsonReader().parse(rawJson);
    Isolate.exit(reply, <Object?>[true, model]);
  } on YosysJsonParseException catch (e) {
    Isolate.exit(reply, <Object?>[false, e.message]);
  } on Object catch (e) {
    Isolate.exit(reply, <Object?>[false, 'Yosys JSON could not be parsed: $e']);
  }
}
