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

/// End-to-end render golden: `adder4` synthesized to sky130_fd_sc_hd
/// (`test/fixtures/gate_level/sky130_fd_sc_hd/`), read by the native
/// gate-level reader with the library, laid out by the native engine and
/// painted by the canvas. Its XNOR gates and the `maj3` boxes, with every
/// cell's supply pins on its top and bottom faces, pin the whole path from
/// the Liberty file to the pixels.
///
/// Painted in the mid band (symbols, no labels) so the image does not hang
/// on font rasterisation. Recorded on the CI renderer only, through the
/// Rebaseline goldens workflow; never re-recorded for a local-only diff.
void main() {
  testWidgets('adder4 on sky130_fd_sc_hd, native read and native layout', (
    tester,
  ) async {
    if (!requireElkFfiLibrary()) return;
    final library = LibertyParser.parseFile(
      'test/fixtures/liberty/pdk/sky130_fd_sc_hd/'
      'sky130_fd_sc_hd__tt_025C_1v80.lib.gz',
    );
    final outcome = readGateLevelNetlist(
      NativeReadRequest(
        sourceFiles: const <String>[
          'test/fixtures/gate_level/sky130_fd_sc_hd/adder4.v',
        ],
        libertyLibraries: <LibertyLibrary>[library],
        topModule: 'adder4',
      ),
    );
    expect(outcome, isA<NativeReadSuccess>());
    final model = (outcome! as NativeReadSuccess).model;
    final top = HierarchyNode.rootOf(model)!;
    final solver = NativeElkSolver.open();
    addTearDown(solver.dispose);
    final laidOut = layOutScope(
      model,
      top,
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
      matchesGoldenFile('goldens/liberty_adder4_sky130.png'),
    );
  });
}
