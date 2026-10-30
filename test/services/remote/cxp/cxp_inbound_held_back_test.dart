// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/project/providers/scope_layout_gate_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/remote/cxp/cxp_inbound_handler.dart';
import 'package:netcrux/services/remote/cxp/editor_open_service.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/held_back_tab_rig.dart';

const PeerIdentity _sender = PeerIdentity(
  peerId: 'held-back-test-sender',
  productName: 'test',
  productVersion: '0.0.0',
);

/// A cross-probe from a peer into a scope held back for being over the layout
/// limit (a flat scope of 30 cells against a limit of 10).
///
/// Whether the element is there is answered from the scope's netlist module.
/// Building the scope's schematic graph to find out walks every cell, which
/// is the cost the limit exists to avoid and, on a netlist of millions of
/// gates, stalls the app when a peer sends a highlight.
///
/// MUTATION: answering any of these from `SchematicGraphBuilder().build`
/// again, as `_currentGraph` did, turns the build count in `highlight` red.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  late HeldBackTabRig rig;
  late NetcruxCxpRequestHandler handler;

  setUp(() async {
    rig = await HeldBackTabRig.open(cells: 30, limit: 10);
    addTearDown(rig.dispose);
    rig.showDesign();
    expect(
      rig.tab.read(scopeLayoutGateProvider).deferred,
      isTrue,
      reason: 'the scope must be held back for this test to mean anything',
    );
    handler = NetcruxCxpRequestHandler(
      rootContainer: rig.root,
      activeTabContainerLookup: () => rig.tab,
      // Never the real service: nothing here may start an editor.
      editorService: EditorOpenService(
        processRunner: (_, _) async => ProcessResult(0, 0, '', ''),
      ),
    );
  });

  /// Sends a highlight for [element] and returns the answer and how many
  /// schematic graphs were built while it was handled.
  Future<({bool honored, int graphsBuilt})> highlight(ElementId element) async {
    final before = SchematicGraphBuilder.buildCount;
    final result = await handler.highlight(
      RequestHighlight(element: element),
      _sender,
    );
    return (
      honored: result.honored,
      graphsBuilt: SchematicGraphBuilder.buildCount - before,
    );
  }

  SelectedElement primary() => rig.tab.read(selectedElementProvider).primary;

  group(
    'request_highlight into a held-back scope builds no schematic graph',
    () {
      test('on an instance', () async {
        final result = await highlight(
          const ElementId(kind: ElementKind.instance, path: 'flat.u7:cell'),
        );
        expect(result.honored, isTrue);
        expect(primary(), const SelectedElement.cell(cellId: 'u7'));
        expect(result.graphsBuilt, 0);
      });

      test('on a cell pin', () async {
        final result = await highlight(
          const ElementId(kind: ElementKind.port, path: 'flat.u7.A'),
        );
        expect(result.honored, isTrue);
        expect(
          primary(),
          const SelectedElement.port(
            cellId: 'u7',
            portId: 'u7:A',
            portName: 'A',
          ),
        );
        expect(result.graphsBuilt, 0);
      });

      test('on a cell named by its path from the top', () async {
        final result = await highlight(
          const ElementId(kind: ElementKind.cell, path: 'flat.u7'),
        );
        expect(result.honored, isTrue);
        expect(primary(), const SelectedElement.cell(cellId: 'u7'));
        expect(result.graphsBuilt, 0);
      });

      test(
        'on a net rooted at the top, with the wire ids the graph gives',
        () async {
          final result = await highlight(
            const ElementId(kind: ElementKind.net, path: 'flat.n5'),
          );
          expect(result.honored, isTrue);
          // n5 is net id 8: driven by u5.Y, read by u6.A.
          expect(
            primary(),
            SelectedElement.wire(edgeId: netEdgeId(8, 0), netId: 8),
          );
          expect(result.graphsBuilt, 0);
        },
      );

      test('on a net with no sink, which falls back to its driver', () async {
        final result = await highlight(
          const ElementId(kind: ElementKind.net, path: 'flat.n29'),
        );
        expect(result.honored, isTrue);
        expect(primary(), const SelectedElement.cell(cellId: 'u29'));
        expect(result.graphsBuilt, 0);
      });

      test('on a net named from a testbench path (leaf match)', () async {
        final result = await highlight(
          const ElementId(kind: ElementKind.signal, path: 'tb.dut.n5'),
        );
        expect(result.honored, isTrue);
        expect(
          primary(),
          SelectedElement.wire(edgeId: netEdgeId(8, 0), netId: 8),
        );
        expect(result.graphsBuilt, 0);
      });

      test('on a boundary port named from a testbench path', () async {
        final result = await highlight(
          const ElementId(kind: ElementKind.signal, path: 'tb.dut.in0'),
        );
        expect(result.honored, isTrue);
        expect(
          primary(),
          const SelectedElement.boundaryPort(
            portId: 'port:in0',
            portName: 'in0',
          ),
        );
        expect(result.graphsBuilt, 0);
      });

      test('on a cell named from a testbench path', () async {
        final result = await highlight(
          const ElementId(kind: ElementKind.signal, path: 'tb.dut.u3'),
        );
        expect(result.honored, isTrue);
        expect(primary(), const SelectedElement.cell(cellId: 'u3'));
        expect(result.graphsBuilt, 0);
      });

      test(
        'declines an element that is not there, also without a build',
        () async {
          for (final element in const <ElementId>[
            ElementId(kind: ElementKind.instance, path: 'flat.u_missing:cell'),
            ElementId(kind: ElementKind.port, path: 'flat.u7.NOPE'),
            ElementId(kind: ElementKind.cell, path: 'flat.u_missing'),
            ElementId(kind: ElementKind.net, path: 'flat.n_missing'),
            ElementId(kind: ElementKind.signal, path: 'tb.dut.n_missing'),
          ]) {
            final result = await highlight(element);
            expect(result.honored, isFalse, reason: element.path);
            expect(result.graphsBuilt, 0, reason: element.path);
          }
          expect(rig.tab.read(selectedElementProvider).isEmpty, isTrue);
        },
      );
    },
  );
}
