// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';

/// Streaming reader for `yosys write_json` output.
///
/// The in-memory [YosysJsonParser] loads the entire document into a
/// single `Map` before constructing a [NetlistModel]. That works for
/// tens-of-thousand-cell designs, but on
/// real-world million-cell designs the document is several hundred
/// megabytes and the Dart heap spike from `jsonDecode` is the
/// dominant memory cost.
///
/// This reader parses incrementally:
///
/// 1. Skim until we hit the `"modules"` key in the top-level object.
/// 2. Walk through the `modules` map one module at a time, tracking
///    brace depth so we can extract each module's JSON sub-document
///    by string slice without materializing the surrounding map.
/// 3. Decode each module sub-document independently and forward it
///    to [Module.fromJson]; emit a [Module] record before reading
///    the next.
///
/// What this does and does not bound: it avoids the `jsonDecode`
/// heap spike — no intermediate `Map` for the whole document is ever
/// built, and decoded-object overhead stays at `O(largest single
/// module)` plus the accumulated `NetlistModel.modules` map. It does
/// **not** bound the raw input: every entry point ends up calling
/// [parse] with the complete document as one `String`, so the source
/// text is fully materialized in memory regardless of how it arrived.
/// [readStream] accumulates the incoming chunks into a `StringBuffer`
/// and [readFile] delegates to it, so neither is incremental in the
/// raw-bytes sense; the desktop elaboration path likewise hands over a
/// `String` the runner already read whole. Whole-document
/// materialization is therefore the known scale ceiling of this
/// reader — the same honest accounting recorded at the
/// `parseNetlistOnIsolate` call site in `loaded_netlist_provider.dart`.
/// Lifting it means a chunk-boundary-aware scanner that can suspend
/// mid-module.
///
/// Behaviorally drop-in compatible with [YosysJsonParser]: the
/// produced [NetlistModel] equals the one [YosysJsonParser] would
/// build from the same input. The two implementations are
/// cross-tested in
/// `test/services/yosys/streaming_yosys_json_reader_test.dart`.
///
/// Cancellation: callers pass a [CancellationToken]; the reader
/// checks it between module emissions and, in [readStream], between
/// incoming chunks, aborting cleanly when set and returning a partial
/// netlist (caller decides whether to discard). This is the seam for
/// callers that drive the reader directly on their own isolate — the
/// web JSON loader and tests. The desktop elaboration path does
/// **not** use it: it runs [parse] on a spawned isolate and cancels by
/// killing that isolate outright, because [parse] is a tight
/// synchronous loop whose event loop never turns, so a cooperative
/// check between modules could not fire. See
/// `isolate_netlist_parser.dart`.
class StreamingYosysJsonReader {
  /// Creates a streaming reader. Stateless; instances are
  /// interchangeable.
  const StreamingYosysJsonReader();

  /// Parses [rawJson] (the full document as a string) incrementally.
  /// Used by tests and by callers that already have the document in
  /// memory but want the per-module emission semantics.
  ///
  /// Throws [YosysJsonParseException] on malformed input.
  NetlistModel parse(
    String rawJson, {
    CancellationToken? cancellation,
  }) {
    final modules = <String, Module>{};
    final creator = _parseScalars(rawJson);
    // The streaming scanner hand-rolls structure detection and calls
    // `jsonDecode` / `Module.fromJson` on substrings, either of which can
    // throw a raw `FormatException` (bad escape in a module-name string) or
    // `TypeError` (a nested member with the wrong shape). Funnel every
    // non-typed leak into a `YosysJsonParseException` so the production
    // path surfaces a typed failure and never a half-built netlist.
    try {
      _parseModules(
        rawJson,
        onModule: (name, json) {
          try {
            modules[name] = Module.fromJson(name, json);
          } on YosysJsonParseException {
            rethrow;
          } on Object catch (e) {
            // Carry the module name as the JSON path.
            throw YosysJsonParseException(
              'Module "$name" has unexpected types: $e',
              cause: e,
            );
          }
        },
        cancellation: cancellation,
      );
    } on YosysJsonParseException {
      rethrow;
    } on Object catch (e) {
      throw YosysJsonParseException(
        'Yosys JSON could not be parsed: $e',
        cause: e,
      );
    }
    return NetlistModel(creator: creator, modules: modules);
  }

  /// Reads the file at [path] and parses it.
  ///
  /// Delegates to [readStream] over `File.openRead()`, so the same
  /// whole-document materialization applies: the file's decoded text is
  /// accumulated in full before parsing begins. Peak memory is the
  /// document size plus `O(largest single module)` of decoded objects.
  Future<NetlistModel> readFile(
    String path, {
    CancellationToken? cancellation,
  }) async {
    final file = File(path);
    final stream = file.openRead();
    return await readStream(stream, cancellation: cancellation);
  }

  /// Reads [stream] (typically `File.openRead()` or a subprocess
  /// stdout) and parses it.
  ///
  /// The chunks are decoded and accumulated into a `StringBuffer`, then
  /// handed to [parse] as one string — the per-module incrementality is
  /// in the *parse*, not in the *read*. [cancellation] is checked after
  /// each chunk, so a cancelled read stops accumulating and returns an
  /// empty netlist without parsing.
  Future<NetlistModel> readStream(
    Stream<List<int>> stream, {
    CancellationToken? cancellation,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      if (cancellation?.isCancelled ?? false) {
        return const NetlistModel(creator: '', modules: <String, Module>{});
      }
    }
    return parse(buffer.toString(), cancellation: cancellation);
  }

  /// Extracts the top-level `creator` scalar (if present) without
  /// materializing the whole document. We use a permissive regex —
  /// the `creator` field appears at the top of every Yosys-written
  /// JSON document and is always a simple ASCII string.
  String _parseScalars(String rawJson) {
    final match = RegExp(r'"creator"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(
      rawJson,
    );
    if (match == null) return '';
    // Unescape JSON string escapes so the value matches what
    // `jsonDecode` would produce. We rely on `jsonDecode` for the
    // unescape work to keep the parser correct for the long tail of
    // escape sequences (`\u00XX`, etc.).
    try {
      return jsonDecode('"${match.group(1)!}"') as String;
    } on FormatException {
      return '';
    }
  }

  /// Streams through the `"modules": { ... }` section, calling
  /// [onModule] once per module with its name and decoded JSON map.
  void _parseModules(
    String rawJson, {
    required void Function(String name, Map<String, Object?> json) onModule,
    CancellationToken? cancellation,
  }) {
    final start = _findModulesStart(rawJson);
    if (start == null) {
      throw const YosysJsonParseException(
        'Yosys JSON is missing a `modules` object',
      );
    }
    var i = start;
    while (i < rawJson.length) {
      // Check the cancellation token at every loop iteration (before
      // we do any work) so the reader aborts promptly even when the
      // user cancels before the first module is processed.
      if (cancellation?.isCancelled ?? false) return;
      i = _skipWhitespace(rawJson, i);
      if (i >= rawJson.length) {
        throw const YosysJsonParseException(
          'Yosys JSON ended mid-modules object',
        );
      }
      final ch = rawJson.codeUnitAt(i);
      if (ch == $closeBrace) break; // end of modules map
      if (ch == $comma) {
        i++;
        continue;
      }
      if (ch != $quote) {
        throw YosysJsonParseException(
          'Expected module name at offset $i, got "${rawJson[i]}"',
        );
      }
      final keyEnd = _findStringEnd(rawJson, i);
      if (keyEnd < 0) {
        throw const YosysJsonParseException(
          'Unterminated module name string',
        );
      }
      final rawName = rawJson.substring(i, keyEnd + 1);
      final name = jsonDecode(rawName) as String;
      i = keyEnd + 1;
      i = _skipWhitespace(rawJson, i);
      if (i >= rawJson.length || rawJson.codeUnitAt(i) != $colon) {
        throw const YosysJsonParseException(
          'Expected colon after module name',
        );
      }
      i++;
      i = _skipWhitespace(rawJson, i);
      if (i >= rawJson.length || rawJson.codeUnitAt(i) != $openBrace) {
        throw const YosysJsonParseException(
          'Expected `{` after module name',
        );
      }
      final valueEnd = _findObjectEnd(rawJson, i);
      if (valueEnd < 0) {
        throw const YosysJsonParseException(
          'Unterminated module value object',
        );
      }
      final raw = rawJson.substring(i, valueEnd + 1);
      final Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException catch (e) {
        throw YosysJsonParseException(
          'Module "$name" has malformed JSON: ${e.message}',
          cause: e,
        );
      }
      if (decoded is! Map<String, Object?>) {
        throw YosysJsonParseException(
          'Module "$name" is not a JSON object',
        );
      }
      onModule(name, decoded);
      i = valueEnd + 1;
      if (cancellation?.isCancelled ?? false) return;
    }
  }

  /// Returns the index of the first byte inside `"modules": {` (the
  /// position immediately after the opening brace), or `null` when
  /// the key is absent.
  int? _findModulesStart(String rawJson) {
    final match = RegExp(r'"modules"\s*:\s*\{').firstMatch(rawJson);
    if (match == null) return null;
    return match.end;
  }

  int _skipWhitespace(String s, int i) {
    var pos = i;
    while (pos < s.length) {
      final ch = s.codeUnitAt(pos);
      if (ch != $space &&
          ch != $tab &&
          ch != $newline &&
          ch != $carriageReturn) {
        return pos;
      }
      pos++;
    }
    return pos;
  }

  /// Returns the index of the closing `"` of the JSON string that
  /// starts at [start]. Honors `\\` and `\"` escapes. Returns `-1`
  /// when the string is unterminated.
  int _findStringEnd(String s, int start) {
    assert(s.codeUnitAt(start) == $quote, 'must start at opening quote');
    var i = start + 1;
    while (i < s.length) {
      final ch = s.codeUnitAt(i);
      if (ch == $backslash) {
        i += 2;
        continue;
      }
      if (ch == $quote) return i;
      i++;
    }
    return -1;
  }

  /// Returns the index of the closing `}` of the JSON object whose
  /// opening `{` is at [start]. Skips strings (so braces inside
  /// strings don't count) and honors escapes. Returns `-1` when the
  /// object is unterminated.
  int _findObjectEnd(String s, int start) {
    assert(s.codeUnitAt(start) == $openBrace, 'must start at opening brace');
    var depth = 0;
    var i = start;
    while (i < s.length) {
      final ch = s.codeUnitAt(i);
      if (ch == $openBrace) {
        depth++;
      } else if (ch == $closeBrace) {
        depth--;
        if (depth == 0) return i;
      } else if (ch == $quote) {
        final end = _findStringEnd(s, i);
        if (end < 0) return -1;
        i = end;
      }
      i++;
    }
    return -1;
  }
}

/// Cooperative cancellation token.
///
/// The streaming reader checks this between module emissions so the
/// UI can drop an in-flight elaboration when the user opens a
/// different design.
class CancellationToken {
  /// Creates an uncancelled token.
  CancellationToken();

  bool _cancelled = false;

  /// Marks the token cancelled. Subsequent reads of [isCancelled]
  /// return true.
  void cancel() {
    _cancelled = true;
  }

  /// True after [cancel] has been called.
  bool get isCancelled => _cancelled;
}

const int $openBrace = 0x7B;
const int $closeBrace = 0x7D;
const int $comma = 0x2C;
const int $colon = 0x3A;
const int $quote = 0x22;
const int $backslash = 0x5C;
const int $space = 0x20;
const int $tab = 0x09;
const int $newline = 0x0A;
const int $carriageReturn = 0x0D;
