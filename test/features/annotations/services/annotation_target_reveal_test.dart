import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/annotations/services/annotation_target_reveal.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// `top` (ports clk, rst, dout; cells u_cpu, dma_reg) instantiates `u_cpu`
/// (module `cpu`: cells u_alu, pc_reg; net pc_q), which instantiates
/// `u_alu` (module `alu`).
NetlistModel _seed() => const YosysJsonParser().parse(
  File(
    'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
  ).readAsStringSync(),
);

ProviderContainer _tab() {
  final tab = ProviderContainer();
  addTearDown(tab.dispose);
  tab.read(hierarchyTreeProvider.notifier).setModel(_seed());
  return tab;
}

String? _module(ProviderContainer tab) =>
    tab.read(hierarchyTreeProvider).selected?.moduleName;

void main() {
  test('a cell in another module navigates there, selects and reveals', () {
    final tab = _tab();
    expect(_module(tab), 'top');
    final found = revealAnnotationTarget(
      tab,
      kind: AnnotationTargetKind.cell,
      targetId: 'pc_reg',
      moduleName: 'cpu',
    );
    expect(found, isTrue);
    expect(_module(tab), 'cpu');
    expect(
      tab.read(selectedElementProvider).primary,
      const SelectedElement.cell(cellId: 'pc_reg'),
    );
    expect(tab.read(revealRequestProvider), 'pc_reg');
  });

  test('a module name that does not declare the cell finds nothing', () {
    final tab = _tab();
    final found = revealAnnotationTarget(
      tab,
      kind: AnnotationTargetKind.cell,
      targetId: 'pc_reg',
      moduleName: 'alu',
    );
    expect(found, isFalse);
    expect(_module(tab), 'top');
    expect(tab.read(selectedElementProvider).isEmpty, isTrue);
  });

  test('without a module name every module is searched by exact name', () {
    final tab = _tab();
    final found = revealAnnotationTarget(
      tab,
      kind: AnnotationTargetKind.cell,
      targetId: 'xor0',
    );
    expect(found, isTrue);
    expect(_module(tab), 'alu');
  });

  test('a pin selects the pin after revealing its cell', () {
    final tab = _tab();
    final found = revealAnnotationTarget(
      tab,
      kind: AnnotationTargetKind.port,
      targetId: 'u_cpu:CLK',
      moduleName: 'top',
    );
    expect(found, isTrue);
    expect(
      tab.read(selectedElementProvider).primary,
      const SelectedElement.port(
        cellId: 'u_cpu',
        portId: 'u_cpu:CLK',
        portName: 'CLK',
      ),
    );
  });

  test('a pin the cell does not have finds nothing', () {
    final tab = _tab();
    expect(
      revealAnnotationTarget(
        tab,
        kind: AnnotationTargetKind.port,
        targetId: 'u_cpu:NOPE',
        moduleName: 'top',
      ),
      isFalse,
    );
  });

  test('a boundary port selects the port of its module', () {
    final tab = _tab();
    final found = revealAnnotationTarget(
      tab,
      kind: AnnotationTargetKind.boundaryPort,
      targetId: 'port:DOUT',
      moduleName: 'cpu',
    );
    expect(found, isTrue);
    expect(_module(tab), 'cpu');
    expect(
      tab.read(selectedElementProvider).primary,
      const SelectedElement.boundaryPort(portId: 'port:DOUT', portName: 'DOUT'),
    );
  });

  test('a scope opens the named instance', () {
    final tab = _tab();
    final found = revealAnnotationTarget(
      tab,
      kind: AnnotationTargetKind.scope,
      targetId: 'u_cpu.u_alu',
    );
    expect(found, isTrue);
    expect(_module(tab), 'alu');
  });

  test('a scope path that starts with the top name also opens', () {
    final tab = _tab();
    expect(
      revealAnnotationTarget(
        tab,
        kind: AnnotationTargetKind.scope,
        targetId: 'top.u_cpu',
      ),
      isTrue,
    );
    expect(_module(tab), 'cpu');
  });

  test('nothing is revealed before a design is loaded', () {
    final tab = ProviderContainer();
    addTearDown(tab.dispose);
    expect(
      revealAnnotationTarget(
        tab,
        kind: AnnotationTargetKind.cell,
        targetId: 'pc_reg',
      ),
      isFalse,
    );
  });

  test('a net reveals by the name of the net carrying the edge', () {
    final tab = _tab();
    final model = tab.read(hierarchyTreeProvider).model!;
    final net = model.modules['cpu']!.nets['pc_q']!;
    final netId = (net.bits.first as NetBit).netId;
    final found = revealAnnotationTarget(
      tab,
      kind: AnnotationTargetKind.net,
      targetId: 'e_${netId}_0',
      moduleName: 'cpu',
    );
    expect(found, isTrue);
    expect(_module(tab), 'cpu');
    final primary = tab.read(selectedElementProvider).primary;
    expect(primary, isA<SelectedElementWire>());
  });
}
