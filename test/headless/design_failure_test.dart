// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A design that was not produced never gives an answer.
//
// `classifyNetDesignProblem` maps what went wrong reading or elaborating a
// design to how a command ends. The oracle below runs every command against
// a Yosys that fails each way it can (not installed, every failure kind the
// runner reports, a timeout, a cancel, a netlist that does not parse) and a
// netlist file that is not one, and lists every run that came back as an
// answer. The mutation proof runs the same oracle with a broken mapping that
// calls every failure `completed` and asserts that the oracle catches it, so
// the oracle cannot be vacuous.

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/headless/net_design.dart';
import 'package:netcrux/headless/netcrux_cli.dart';
import 'package:path/path.dart' as p;

import 'support/fake_elaborator.dart';

YosysRunFailure _failure(YosysFailureKind kind) => YosysRunFailure(
  exitCode: kind == YosysFailureKind.nonZeroExit ? 1 : -1,
  stdout: '',
  stderr: 'ERROR: ${kind.name}\n',
  kind: kind,
);

/// Every way Yosys can fail to give a design, by name.
final Map<String, FakeElaborator Function()> _yosysFailures =
    <String, FakeElaborator Function()>{
      'Yosys not installed': () =>
          FakeElaborator(_failure(YosysFailureKind.launch), available: false),
      for (final kind in YosysFailureKind.values)
        'a run that fails (${kind.name})': () => FakeElaborator(_failure(kind)),
      'a run that times out': () => FakeElaborator(
        const YosysRunTimeout(
          budget: Duration(seconds: 30),
          stdout: '',
          stderr: '',
        ),
      ),
      'a run that is cancelled': () => FakeElaborator(
        const YosysRunCancelled(stdout: '', stderr: ''),
      ),
      'a netlist Yosys wrote that does not parse': () => FakeElaborator(
        const YosysRunSuccess(
          rawJson: '{"modules": 7}',
          stdout: '',
          stderr: '',
        ),
      ),
    };

/// Each command's arguments after its name, for [design].
List<List<String>> _commands(List<String> design) => <List<String>>[
  <String>['info', ...design, '--json'],
  <String>['search', ...design, 'a', '--json'],
  <String>['connections', ...design, 'top.n', '--json'],
];

/// The runs that ended as an answer although no design was produced, or
/// wrote no valid document: empty when [map] never lets a failure through.
Future<List<String>> _answersFromFailedDesigns(
  NetDesignProblemMap map,
  String badNetlist,
) async {
  final sources = <String>[
    p.absolute('spec', 'fixtures', 'top.v'),
    p.absolute('spec', 'fixtures', 'inc.v'),
  ];
  final runs = <(String, FakeElaborator Function(), List<String>)>[
    for (final f in _yosysFailures.entries) (f.key, f.value, sources),
    (
      'a netlist file that is not one',
      FakeElaborator.failing,
      <String>[badNetlist],
    ),
  ];
  final problems = <String>[];
  for (final (label, elaborator, design) in runs) {
    for (final args in _commands(design)) {
      final cli = NetCruxCli(
        reader: NetDesignReader(elaborator: elaborator()),
        telemetry: () => null,
        mapProblem: map,
      );
      final out = StringBuffer();
      final run = '$label: ${args.first}';
      int code;
      try {
        code = await cli.run(args, out: out, err: StringBuffer());
      } on Object catch (e) {
        problems.add('$run threw $e');
        continue;
      }
      final outcome = mcpDocumentOutcome(out.toString());
      if (outcome == null) {
        problems.add('$run wrote no document');
      } else if (outcome.isAnswer) {
        problems.add('$run answered ${outcome.wireName}');
      } else if (code == 0) {
        problems.add('$run exited 0');
      }
    }
  }
  return problems;
}

void main() {
  late Directory scratch;
  late String badNetlist;

  setUpAll(() {
    scratch = Directory.systemTemp.createTempSync('netcrux_design_failure_');
    badNetlist = p.join(scratch.path, 'broken.json');
    File(badNetlist).writeAsStringSync('{"creator": "x", "modules": [1]}');
  });

  tearDownAll(() => scratch.deleteSync(recursive: true));

  final runCount = (_yosysFailures.length + 1) * 3;

  test('no design problem becomes an answer', () async {
    expect(
      await _answersFromFailedDesigns(classifyNetDesignProblem, badNetlist),
      isEmpty,
    );
  });

  test(
    'mutation proof: a mapping that calls a Yosys failure completed is caught',
    () async {
      NetDesignFailure broken(NetDesignProblem problem) =>
          const NetDesignFailure(
            McpOutcome.completed,
            McpDiagnostic(
              severity: McpSeverity.note,
              code: 'engine.failed',
              message: 'ignored',
            ),
          );
      final problems = await _answersFromFailedDesigns(broken, badNetlist);
      // Every run of the oracle reports the mutant, not just one.
      expect(problems, hasLength(runCount));
      expect(
        problems.where((p) => p.contains('answered completed')),
        hasLength(
          runCount,
        ),
      );
    },
  );

  test(
    'mutation proof: a mapping that drops the engine error is caught',
    () async {
      // The subtler break: the outcome right, the reason gone. A document
      // without its error diagnostic is never written, so the run fails loudly.
      NetDesignFailure silent(NetDesignProblem problem) =>
          const NetDesignFailure(
            McpOutcome.engineError,
            McpDiagnostic(
              severity: McpSeverity.warning,
              code: 'engine.failed',
              message: 'ignored',
            ),
          );
      expect(
        await _answersFromFailedDesigns(silent, badNetlist),
        hasLength(runCount),
      );
    },
  );

  group('classifyNetDesignProblem', () {
    test('a missing, failed or timed-out Yosys is the engine', () {
      for (final problem in <NetDesignProblem>[
        const YosysUnavailable(YosysAvailability.notFound()),
        YosysDidNotElaborate(_failure(YosysFailureKind.launch)),
        YosysDidNotElaborate(_failure(YosysFailureKind.nonZeroExit)),
        YosysDidNotElaborate(_failure(YosysFailureKind.noOutput)),
        YosysDidNotElaborate(_failure(YosysFailureKind.outputUnreadable)),
        const YosysDidNotElaborate(
          YosysRunTimeout(budget: Duration(seconds: 3), stdout: '', stderr: ''),
        ),
        const NetlistUnreadable('/x.json', 'bad', fromYosys: true),
      ]) {
        final f = classifyNetDesignProblem(problem);
        expect(f.outcome, McpOutcome.engineError, reason: '$problem');
        expect(f.diagnostic.severity, McpSeverity.error);
        expect(f.diagnostic.code, startsWith('engine.'));
      }
    });

    test('a request Yosys cannot take, or a netlist file that is not one, is '
        "the input's", () {
      for (final problem in <NetDesignProblem>[
        YosysDidNotElaborate(_failure(YosysFailureKind.invalidRequest)),
        const NetlistUnreadable('/x.json', 'bad', fromYosys: false),
      ]) {
        final f = classifyNetDesignProblem(problem);
        expect(f.outcome, McpOutcome.inputError, reason: '$problem');
        expect(f.diagnostic.code, startsWith('input.'));
      }
    });

    test("Yosys's own error line reaches the reader", () {
      final f = classifyNetDesignProblem(
        const YosysDidNotElaborate(
          YosysRunFailure(
            exitCode: 1,
            stdout: '',
            stderr:
                'Parsing top.v\n'
                "top.v:3: ERROR: syntax error, unexpected ';'\n"
                'End of script.\n',
            kind: YosysFailureKind.nonZeroExit,
          ),
        ),
      );
      expect(
        f.diagnostic.message,
        'Yosys stopped with exit code 1: top.v:3: ERROR: syntax error, '
        "unexpected ';'",
      );
    });

    test('the timeout says its budget', () {
      final f = classifyNetDesignProblem(
        const YosysDidNotElaborate(
          YosysRunTimeout(
            budget: Duration(seconds: 45),
            stdout: '',
            stderr: '',
          ),
        ),
      );
      expect(f.diagnostic.code, 'engine.timeout');
      expect(f.diagnostic.message, contains('45 s'));
    });
  });
}
