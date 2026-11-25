// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:netcrux/headless/net_design.dart';

/// The banner the fake Yosys reports: version `0.0+fake`.
const String kFakeYosysBanner = 'Yosys 0.0+fake (hand-made for tests)';

/// Where the fake Yosys says it lives.
const String kFakeYosysPath = '/fake/yosys';

/// A Yosys that never runs: it answers the probe as [availability] says and
/// every run with [result], and records each request.
class FakeElaborator implements NetElaborator {
  /// A Yosys that is found and answers every run with [result].
  FakeElaborator(
    this.result, {
    this.available = true,
    this.executablePath = kFakeYosysPath,
  });

  /// A Yosys that elaborates every design into the netlist in [jsonFile].
  factory FakeElaborator.writing(
    String jsonFile, {
    String executablePath = kFakeYosysPath,
  }) => FakeElaborator(
    YosysRunSuccess(
      rawJson: File(jsonFile).readAsStringSync(),
      stdout: '',
      stderr: '',
    ),
    executablePath: executablePath,
  );

  /// A Yosys that stops with exit code 1 and a syntax error.
  factory FakeElaborator.failing() => FakeElaborator(
    const YosysRunFailure(
      exitCode: 1,
      stdout: '',
      stderr:
          "top.v:3: ERROR: syntax error, unexpected ';'\n"
          'End of script.\n',
      kind: YosysFailureKind.nonZeroExit,
    ),
  );

  /// The run's answer.
  final YosysRunResult result;

  /// Whether the probe finds it.
  final bool available;

  /// The path the probe reports: a bare command name such as `yosys` when
  /// Yosys was found on `PATH`.
  final String executablePath;

  /// Every request run, in order.
  final List<YosysRunRequest> requests = <YosysRunRequest>[];

  @override
  Future<YosysAvailability> probe() async => available
      ? YosysAvailability.available(
          executablePath: executablePath,
          versionString: kFakeYosysBanner,
        )
      : const YosysAvailability.notFound();

  @override
  Future<bool> probeSlang() async => false;

  @override
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    requests.add(request);
    return result;
  }
}
