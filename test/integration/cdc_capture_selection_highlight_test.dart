// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// End-to-end regression for the live CDC bug: after elaborating the real
// `cdc_capture` design through yosys, a local "select this net" gesture
// (the CDC panel row-tap path, i.e. AnalysisSelectionProbe.selectNet)
// must produce a wire selection that the REAL SchematicPainter draws with
// the selection accent — even though the probe resolves the edge id from a
// freshly-built schematic graph whose id numbering diverges from the
// laid-out edge ids the canvas renders.
//
// Yosys-gated: skips when yosys is not on PATH (same policy as the Verilog
// pipeline integration test).
@TestOn('vm')
library;

import 'dart:convert';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/theme/netcrux_colors.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/features/viewer/services/analysis_selection_probe.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

const _verilogPath = 'test/fixtures/verilog/cdc_capture.v';
const _topModule = 'cdc_capture';

/// A scripted [ElkJsHost] that lays nodes out in a row AND echoes every
/// input edge back with a short two-point route, preserving the edge id
/// `buildElkInput` assigned. This reproduces the production divergence:
/// the laid-out edge ids come from `buildElkInput`, while the schematic
/// graph the probe selects against is numbered by `SchematicGraphBuilder`.
class _EchoEdgesHost implements ElkJsHost {
  Map<String, Object?>? _lastInput;

  @override
  String evaluate(String code) {
    if (code.contains('__elkInstance')) return '';
    if (code.contains('"pending"')) return 'done';
    if (code.contains('__elk_error')) return '';
    if (code.contains('__elk_input = ')) {
      final eq = code.indexOf('= ');
      if (eq != -1) {
        final tail = code.substring(eq + 2).trimRight();
        final json = tail.replaceAll(RegExp(r';\s*$'), '');
        try {
          final decoded = jsonDecode(json);
          if (decoded is Map<String, Object?>) _lastInput = decoded;
        } on FormatException {
          _lastInput = null;
        }
      }
      return '';
    }
    if (code.contains('__elk_result')) {
      final input = _lastInput;
      if (input == null) return '';
      final children =
          (input['children'] as List<Object?>?) ?? const <Object?>[];
      final laidOutNodes = <Map<String, Object?>>[
        for (var i = 0; i < children.length; i++)
          <String, Object?>{
            'id': (children[i]! as Map<String, Object?>)['id'],
            'x': 40.0 + (i * 120),
            'y': 40.0,
            'width': 80.0,
            'height': 32.0,
          },
      ];
      final inputEdges =
          (input['edges'] as List<Object?>?) ?? const <Object?>[];
      final laidOutEdges = <Map<String, Object?>>[
        for (var i = 0; i < inputEdges.length; i++)
          <String, Object?>{
            'id': (inputEdges[i]! as Map<String, Object?>)['id'],
            'sections': <Map<String, Object?>>[
              <String, Object?>{
                'startPoint': <String, Object?>{'x': 20.0, 'y': 20.0 + i},
                'endPoint': <String, Object?>{'x': 300.0, 'y': 20.0 + i},
              },
            ],
          },
      ];
      return jsonEncode(<String, Object?>{
        'id': 'root',
        'x': 0.0,
        'y': 0.0,
        'width': 40.0 + (children.length * 120) + 40.0,
        'height': 160.0,
        'children': laidOutNodes,
        'edges': laidOutEdges,
      });
    }
    return '';
  }

  @override
  int executePendingJob() => 0;

  @override
  void dispose() {}
}

/// Paints [laidOut] with [selection] through the real render object and
/// returns whether any wire was stroked with the selection accent.
bool _paintsWireAccent(LaidOutGraph laidOut, Selection selection) {
  final renderObject = SchematicCanvasRenderObject(
    laidOut: laidOut,
    transform: ViewportTransform.identity,
    theme: ThemeData.light(),
    selection: selection,
    statsSink: const NoopRenderStatsSink(),
  )..layout(BoxConstraints.tight(const Size(400, 200)));
  final context = TestRecordingPaintingContext(TestRecordingCanvas());
  renderObject.paint(context, Offset.zero);
  return _accentedEdgeCount(laidOut, selection) > 0;
}

/// Paints [laidOut] with [selection] and counts how many edges were
/// stroked with the bright selected-wire CORE color — i.e. how many
/// strands got the selection accent. A multi-bit bus must light every
/// drawn strand, not one.
int _accentedEdgeCount(LaidOutGraph laidOut, Selection selection) {
  final renderObject = SchematicCanvasRenderObject(
    laidOut: laidOut,
    transform: ViewportTransform.identity,
    theme: ThemeData.light(),
    selection: selection,
    statsSink: const NoopRenderStatsSink(),
    // Cull nothing so the count reflects every laid-out strand, not just
    // the ones inside a 400×200 window of a wide row layout.
    cullingEnabled: false,
  )..layout(BoxConstraints.tight(const Size(400, 200)));
  final context = TestRecordingPaintingContext(TestRecordingCanvas());
  renderObject.paint(context, Offset.zero);
  final canvas = context.canvas as TestRecordingCanvas;
  final core = NetcruxColors.selectedWireCore.toARGB32();
  var count = 0;
  for (final recorded in canvas.invocations) {
    final invocation = recorded.invocation;
    if (invocation.memberName == #drawPath) {
      final paint = invocation.positionalArguments[1] as Paint;
      if (paint.color.toARGB32() == core) count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cdc_capture selection highlight (real yosys)', () {
    late bool yosysAvailable;

    setUpAll(() async {
      final probe = await YosysAvailabilityService(
        runner: const DefaultProcessRunner(),
      ).probe();
      yosysAvailable = probe.isAvailable;
    });

    test(
      'local row-tap: selectNet("sample_a") paints the schematic accent',
      () async {
        if (!yosysAvailable) {
          markTestSkipped('yosys not on PATH — install yosys to run this');
          return;
        }
        // 1. Elaborate the real design.
        final result = await YosysRunner().run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile(_verilogPath)],
            topModule: _topModule,
          ),
        );
        expect(
          result,
          isA<YosysRunSuccess>(),
          reason: result is YosysRunFailure
              ? 'yosys exited ${result.exitCode}: ${result.stderr}'
              : null,
        );
        final model = const YosysJsonParser().parse(
          (result as YosysRunSuccess).rawJson,
        );
        expect(model.modules.keys, contains(_topModule));

        // 2. Per-tab container with the model; the top scope is selected.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(hierarchyTreeProvider.notifier).setModel(model);
        final node = container.read(hierarchyTreeProvider).selected;
        expect(node, isNotNull, reason: 'top scope should be selected');

        // 3. Real laid-out graph (real graph builder + a layout whose edge
        //    ids come from buildElkInput — the production divergence).
        final module = node!.resolve(model)!;
        final graph = const SchematicGraphBuilder().build(model, node);
        final layout = await ElkLayoutService(
          hostFactory: _EchoEdgesHost.new,
          assetLoader: (_) async => '// echo host',
        ).layout(module);
        final laidOut = LaidOutGraph(graph: graph, layout: layout);
        expect(laidOut.isEmpty, isFalse);

        // 4. The CDC row-tap path: select the crossing net by name.
        final probe = AnalysisSelectionProbe(container);
        final selected = probe.selectNet('sample_a');
        expect(
          selected,
          isTrue,
          reason: 'sample_a should resolve to a rendered wire',
        );
        final selection = container.read(selectedElementProvider);
        expect(selection.primary, isA<SelectedElementWire>());
        final wire = selection.primary as SelectedElementWire;
        expect(wire.netId, greaterThanOrEqualTo(0));

        // The net the probe selected has a laid-out edge (by net id) — the
        // stable key the painter now highlights on.
        final laidOutNetIds = layout.edges
            .map((e) => e.netId)
            .whereType<int>()
            .toSet();
        expect(laidOutNetIds, contains(wire.netId));

        // 5. The real painter draws the accent for that selection.
        expect(_paintsWireAccent(laidOut, selection), isTrue);

        // 6. WHOLE-BUS highlight: sample_a is an 8-bit bus (8 Yosys net
        //    ids). The selection must carry one wire per bit that has a
        //    drawn edge, and the painter must accent EVERY laid-out edge
        //    carrying one of those net ids (a bit may fan out to several
        //    sinks) — not just one faint strand.
        final selectedNetIds = selection.elements
            .whereType<SelectedElementWire>()
            .map((w) => w.netId)
            .toSet();
        // More than one distinct bit of the bus is drawn (the old bug lit
        // exactly one).
        final drawnSelectedStrands = selectedNetIds
            .where(laidOutNetIds.contains)
            .length;
        expect(
          drawnSelectedStrands,
          greaterThan(1),
          reason: 'sample_a is a multi-bit bus; >1 strand should be drawn',
        );
        // Every laid-out edge carrying a selected net id must be accented.
        final expectedAccented = layout.edges
            .where((e) => e.netId != null && selectedNetIds.contains(e.netId))
            .length;
        expect(expectedAccented, greaterThan(1));
        expect(
          _accentedEdgeCount(laidOut, selection),
          expectedAccented,
          reason: 'every drawn bus strand of sample_a must be accented',
        );
      },
    );
  });
}
