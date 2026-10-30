// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show File, FileSystemException;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/web/web_json_loader.dart';
import 'package:netcrux/services/yosys/black_box_port_inference.dart';
import 'package:netcrux/services/yosys/isolate_netlist_parser.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

/// Reads the text of the netlist document at a location: a file path on
/// desktop, a URL (including a `blob:` URL from a browser upload) on web.
typedef NetlistDocumentReader = Future<String> Function(String location);

/// Loads a pre-built Yosys JSON netlist — the `yosys write_json` output a
/// synthesis flow already produced — without running Yosys.
///
/// This is the only way a design reaches the browser build, which cannot
/// spawn the Yosys subprocess, and on desktop it serves a `.json` netlist
/// opened directly, named by a `<design>.crux-project` manifest, or picked as
/// a comparison design.
///
/// [parseOnIsolate] is on everywhere but web: desktop parses on a background
/// isolate so a large netlist never freezes the UI, while the browser has no
/// `Isolate.spawn` and parses in place.
class PrebuiltNetlistLoader {
  /// Creates a loader. With no [read], a desktop build parses the file at the
  /// location straight from the disk in chunks, so a netlist of any size
  /// opens, and a browser build fetches the URL as text ([fetchWebJson]). A
  /// [read] given here always takes the text route, which tests and the
  /// browser use.
  const PrebuiltNetlistLoader({
    this._read,
    this.parseOnIsolate = !kIsWeb,
  });

  final NetlistDocumentReader? _read;

  /// Whether [parse] runs on a spawned isolate.
  final bool parseOnIsolate;

  /// Reads and parses the netlist at [location], with the pins of its black
  /// boxes and the pins its modules do not declare given directions
  /// ([loadWithReport]).
  ///
  /// Throws [WebJsonLoadException] when the document cannot be read and
  /// `YosysJsonParseException` when it is not a Yosys netlist. Completes with
  /// `null` only when [cancelSignal] fires before the parse finishes.
  Future<NetlistModel?> load(
    String location, {
    Future<void>? cancelSignal,
  }) async =>
      (await loadWithReport(location, cancelSignal: cancelSignal))?.model;

  /// [load], and the report of the pins whose direction was inferred.
  ///
  /// Yosys run from a user's own script (`read_liberty -lib` drops a cell's
  /// power and ground pins, `hierarchy` without `-check` keeps what is left
  /// over) writes a direction of `output` for every connection to a pin the
  /// cell's module does not declare, so every supply net reads as driven by
  /// every cell on it. A connection to a pin the module of its cell does not
  /// declare therefore gets its direction from the wiring, as it does when
  /// NetCrux runs Yosys itself with the black-box option on
  /// ([inferBlackBoxPorts]). A cell whose type no module defines gets the
  /// same, whatever the project's black-box option says: the option decides
  /// whether NetCrux's own Yosys run may leave a missing module in, and here
  /// the netlist is already written. Without it every pin of such a cell
  /// would be drawn as an input and no net on one would have a driver.
  Future<({NetlistModel model, BlackBoxReport report})?> loadWithReport(
    String location, {
    Future<void>? cancelSignal,
  }) async {
    final read = _read;
    if (read == null && parseOnIsolate && !kIsWeb) {
      return await _loadFile(location, cancelSignal: cancelSignal);
    }
    final raw = await (read ?? fetchWebJson)(location);
    return await parseWithReport(raw, cancelSignal: cancelSignal);
  }

  /// The desktop route: the worker isolate reads the file itself, in
  /// chunks, so the document is never a string or one buffer and has no size
  /// limit.
  Future<({NetlistModel model, BlackBoxReport report})?> _loadFile(
    String location, {
    Future<void>? cancelSignal,
  }) async {
    final path = location.startsWith('file://')
        ? Uri.parse(location).toFilePath()
        : location;
    final file = File(path);
    if (!file.existsSync()) {
      throw WebJsonLoadException('JSON file not found at $path');
    }
    try {
      file.openSync().closeSync();
    } on FileSystemException catch (e) {
      throw WebJsonLoadException('Failed to read JSON at $path', cause: e);
    }
    return await parseNetlistFileWithBlackBoxesOnIsolate(
      path,
      cancelSignal: cancelSignal,
    );
  }

  /// Parses an already-read netlist document.
  Future<NetlistModel?> parse(
    String raw, {
    Future<void>? cancelSignal,
  }) async => (await parseWithReport(raw, cancelSignal: cancelSignal))?.model;

  /// [parse], and the report of the pins whose direction was inferred.
  Future<({NetlistModel model, BlackBoxReport report})?> parseWithReport(
    String raw, {
    Future<void>? cancelSignal,
  }) async {
    if (parseOnIsolate) {
      return await parseNetlistWithBlackBoxesOnIsolate(
        raw,
        cancelSignal: cancelSignal,
      );
    }
    return inferBlackBoxPorts(const StreamingYosysJsonReader().parse(raw));
  }
}
