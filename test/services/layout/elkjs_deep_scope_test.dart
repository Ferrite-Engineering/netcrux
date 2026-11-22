// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// netcrux#83: elkjs on the layout worker, on scopes deep enough to reach its
// stack. Every test drives the real worker isolate with elkjs on the
// JavaScript engine the platform picks (JavaScriptCore on macOS,
// JavaScriptCore or QuickJS on Linux), because the failures it guards
// against live in that thread's stack. Where flutter_js cannot load an
// engine under `flutter test` (Windows), the tests skip.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/layout_engine_selection.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';
import 'package:netcrux/services/schematic/schematic_scope_module.dart';

import '../../helpers/elk_ffi_library_gate.dart';
import '../../helpers/layout_parity.dart';

Future<String> _elkBundle(String _) async =>
    File('assets/elk/elk.bundled.js').readAsStringSync();

NetlistModel _model(String fixture) {
  final bytes = File('test/fixtures/netlist/$fixture').readAsBytesSync();
  final text = fixture.endsWith('.gz')
      ? utf8.decode(gzip.decode(bytes))
      : utf8.decode(bytes);
  return NetlistModel.fromJson(jsonDecode(text) as Map<String, Object?>);
}

/// The VexRiscv core as the schematic lays it out: 1,463 cells whose long
/// edges chain thousands of dummy ports, the scope the issue was found on.
Module _vexRiscv() {
  final model = _model('vexriscv/captured/vexriscv.netlist.json.gz');
  return schematicScopeModule(model, model.modules['VexRiscv']!);
}

/// A chain of 10,000 inverters: deeper than any of elkjs's recursive walks
/// can follow on a worker thread, on either JavaScript engine.
Module _chain10k() => _model(
  'chain_10k/generated/chain_10k.netlist.json.gz',
).modules['chain_10k']!;

/// Whether [e] says no JavaScript engine could start here, after marking
/// the test skipped.
bool _skipWithoutEngine(LayoutException e) {
  if (!e.message.contains('Failed to load dynamic library')) return false;
  markTestSkipped('no JavaScript engine for elkjs here: ${e.message}');
  return true;
}

void main() {
  test(
    'elkjs out of stack: reported as such across the worker boundary when '
    'there is no native engine to fall back to',
    () async {
      final service = ElkLayoutService(
        assetLoader: _elkBundle,
        workerSolver: LayoutSolverKind.elkjs,
        fallBackToNative: false,
      );
      addTearDown(service.dispose);
      try {
        await service.layout(_chain10k());
        fail('elkjs laid out a 10,000-cell chain on a worker thread');
      } on LayoutException catch (e) {
        if (_skipWithoutEngine(e)) return;
        expect(e.kind, LayoutFailureKind.outOfStack, reason: e.message);
        expect(e.message, contains('ran out of stack'));
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'elkjs out of stack: the scope is laid out again on the native engine, '
    'which the worker keeps',
    () async {
      if (!requireElkFfiLibrary()) return;
      final service = ElkLayoutService(
        assetLoader: _elkBundle,
        workerSolver: LayoutSolverKind.elkjs,
      );
      addTearDown(service.dispose);
      final chain = _chain10k();
      final NetlistLayout layout;
      try {
        layout = await service.layout(chain);
      } on LayoutException catch (e) {
        if (_skipWithoutEngine(e)) return;
        rethrow;
      }
      // 10,000 cells, and the chain's boundary ports.
      expect(layout.nodes.length, greaterThan(10000));
      expect(service.workerEngine, startsWith('native'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  // JavaScriptCore runs VexRiscv through elkjs in about 20 seconds on the
  // worker thread; QuickJS takes minutes, so the test is not registered
  // where it would run (Linux, Windows).
  if (Platform.isMacOS) {
    test(
      'elkjs lays out VexRiscv on the worker thread, coordinate for '
      'coordinate as the native engine does',
      () async {
        final service = ElkLayoutService(
          assetLoader: _elkBundle,
          workerSolver: LayoutSolverKind.elkjs,
          fallBackToNative: false,
        );
        addTearDown(service.dispose);
        final module = _vexRiscv();
        final layout = await service.layout(module);
        expect(service.workerEngine, startsWith('elkjs'));
        if (!requireElkFfiLibrary()) return;
        final solver = NativeElkSolver.open();
        addTearDown(solver.dispose);
        final native = parseLayout(
          solver.solve(jsonEncode(buildElkInput(module))),
        );
        final diffs = layoutDifferences(layout, native);
        expect(diffs, isEmpty, reason: diffs.take(8).join('\n'));
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
