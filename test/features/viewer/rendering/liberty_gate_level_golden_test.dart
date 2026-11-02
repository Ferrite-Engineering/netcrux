// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/services/export/scope_render.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';
import 'package:netcrux/services/liberty/liberty_cell_index.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:netcrux/services/verilog/native_netlist_reader.dart';

import '../../../helpers/elk_ffi_library_gate.dart';

/// End-to-end render goldens of gate-level netlists on sky130_fd_sc_hd, read
/// by the native gate-level reader with the library, laid out by the native
/// engine and painted by the canvas, pinning the whole path from the Liberty
/// file to the pixels.
///
/// - `adder4` synthesized (`test/fixtures/gate_level/sky130_fd_sc_hd/`): its
///   XNOR gates and `maj3` boxes, with no supply pins, since a netlist
///   straight out of synthesis connects none.
/// - `powered` (`test/fixtures/gate_level/sky130_fd_sc_hd_powered/`), wired
///   as place and route writes it: every supply pin on the top and bottom
///   faces, the one left unconnected on purpose among them.
///
/// Painted in the mid band (symbols, no labels) so the image does not hang
/// on font rasterisation. Recorded on the CI renderer only, through the
/// Rebaseline goldens workflow; never re-recorded for a local-only diff.
void main() {
  Future<void> expectRender(
    WidgetTester tester, {
    required String source,
    required String top,
    required String golden,
  }) async {
    final library = LibertyParser.parseFile(
      'test/fixtures/liberty/pdk/sky130_fd_sc_hd/'
      'sky130_fd_sc_hd__tt_025C_1v80.lib.gz',
    );
    final outcome = readGateLevelNetlist(
      NativeReadRequest(
        sourceFiles: <String>[source],
        libertyLibraries: <LibertyLibrary>[library],
        topModule: top,
      ),
    );
    expect(outcome, isA<NativeReadSuccess>());
    final model = (outcome! as NativeReadSuccess).model;
    final root = HierarchyNode.rootOf(model)!;
    final solver = NativeElkSolver.open();
    addTearDown(solver.dispose);
    final laidOut = layOutScope(
      model,
      root,
      solver.solve,
      liberty: LibertyCellIndex(<LibertyLibrary>[library]).symbolsFor(model),
    );

    const zoom = 0.5;
    final bounds = laidOut.layout.bounds;
    final size = Size(bounds.width * zoom + 16, bounds.height * zoom + 16);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() async => await tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: bounds.width * zoom,
              height: bounds.height * zoom,
              child: SchematicCanvas(
                laidOut: laidOut,
                transform: const ViewportTransform(
                  zoom: zoom,
                  offset: Offset.zero,
                ),
                statsSink: const NoopRenderStatsSink(),
                theme: ThemeData.light(useMaterial3: true),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(SchematicCanvas),
      matchesGoldenFile(golden),
    );
  }

  testWidgets('adder4 on sky130_fd_sc_hd, native read and native layout', (
    tester,
  ) async {
    if (!requireElkFfiLibrary()) return;
    await expectRender(
      tester,
      source: 'test/fixtures/gate_level/sky130_fd_sc_hd/adder4.v',
      top: 'adder4',
      golden: 'goldens/liberty_adder4_sky130.png',
    );
  });

  testWidgets('a powered netlist on sky130_fd_sc_hd draws every supply pin', (
    tester,
  ) async {
    if (!requireElkFfiLibrary()) return;
    await expectRender(
      tester,
      source: 'test/fixtures/gate_level/sky130_fd_sc_hd_powered/powered.v',
      top: 'powered',
      golden: 'goldens/liberty_powered_sky130.png',
    );
  });
}
