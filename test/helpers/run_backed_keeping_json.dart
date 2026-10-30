// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';

/// Lets a test double that overrides only [YosysRunner.run] stand in for
/// Yosys in the elaboration pipeline.
///
/// The pipeline asks for the `write_json` document as a file
/// ([YosysRunner.runKeepingJson]) so a design of any size never becomes one
/// string. A double that fakes `run` returns the text, so this writes that
/// text to a temp file and answers with the path, as the real runner does.
/// The pipeline deletes the file when it is done with it.
mixin RunBackedKeepingJson on YosysRunner {
  static int _next = 0;

  /// The temp files this double has handed out, for a test that checks the
  /// pipeline removes them.
  final List<String> keptDocuments = <String>[];

  @override
  Future<YosysRunResult> runKeepingJson(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(String line)? onStderrLine,
    Map<String, String>? environment,
  }) async {
    final result = await run(
      request,
      timeout: timeout,
      cancelSignal: cancelSignal,
      onStderrLine: onStderrLine,
      environment: environment,
    );
    if (result is! YosysRunSuccess || result.jsonPath != null) return result;
    final file = File(
      '${Directory.systemTemp.path}/netcrux_fake_run_${pid}_${_next++}.json',
    )..writeAsStringSync(result.rawJson);
    keptDocuments.add(file.path);
    return YosysRunSuccess(
      rawJson: '',
      jsonPath: file.path,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }
}
