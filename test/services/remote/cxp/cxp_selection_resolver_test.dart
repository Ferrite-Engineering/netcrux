// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/services/remote/cxp/cxp_selection_resolver.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// The planted-CDC design under test, a copy of the EDACrux scenario design
/// kept in this repo's fixtures so the yosys-gated end-to-end test does not
/// depend on another checkout.
const String _cdcCaptureVPath = 'test/fixtures/verilog/cdc_capture.v';

/// The FSM deadlock design whose top-level `output reg [2:0] state` is the
/// boundary-port that regressed the cross-probe identity path. A fixture copy
/// like [_cdcCaptureVPath].
const String _fsmLockVPath = 'test/fixtures/verilog/fsm_lock.v';

/// The reset-domain design whose `reg alarm_r; assign alarm = alarm_r;` folds
/// (after proc + opt_clean) into ONE net carrying both the internal reg alias
/// `alarm_r` and the output-port alias `alarm`. A fixture copy like
/// [_cdcCaptureVPath].
const String _resetDomainsVPath = 'test/fixtures/verilog/reset_domains.v';

NetlistModel _model() {
  const top = Module(
    name: 'top',
    attributes: <String, String>{'top': '1'},
    ports: {},
    cells: <String, Cell>{
      'u_cpu': Cell(
        name: 'u_cpu',
        type: 'cpu',
        parameters: {},
        attributes: {},
        portDirections: {},
        connections: {},
      ),
    },
    nets: {},
  );
  const cpu = Module(
    name: 'cpu',
    attributes: <String, String>{},
    ports: {},
    cells: {},
    nets: {},
  );
  return const NetlistModel(
    creator: 'test',
    modules: <String, Module>{'top': top, 'cpu': cpu},
  );
}

({NetlistModel? model, HierarchyNode? scope}) _loadedTree() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(hierarchyTreeProvider.notifier).setModel(_model());
  final tree = container.read(hierarchyTreeProvider);
  return (model: tree.model, scope: tree.selected);
}

void main() {
  group('unresolvable inputs', () {
    test('an empty selection resolves to null', () {
      expect(
        resolveCxpSelection(
          element: const SelectedElement.none(),
          model: _loadedTree().model,
          scope: _loadedTree().scope,
        ),
        isNull,
      );
    });

    test('an unloaded tree resolves to null', () {
      expect(
        resolveCxpSelection(
          element: const SelectedElement.cell(cellId: 'u_cpu'),
          model: null,
          scope: null,
        ),
        isNull,
      );
    });
  });

  group('canonical mapping', () {
    test('a cell resolves to a clean dot-joined instance path', () {
      final resolved = resolveCxpSelection(
        element: const SelectedElement.cell(cellId: 'u_cpu'),
        model: _loadedTree().model,
        scope: _loadedTree().scope,
      )!;
      expect(resolved.element.kind, ElementKind.instance);
      // No `:cell` marker: a receiver leaf-matches the bare instance name.
      expect(resolved.element.path, 'top.u_cpu');
      expect(resolved.element.path, isNot(contains(':cell')));
      expect(resolved.element.path.split('.').last, 'u_cpu');
      expect(resolved.displayName, 'u_cpu');
      expect(resolved.scopePath, isNotEmpty);
    });

    test(
      'A register cell resolves to its Q-output net name (kind: net), '
      'not the synthesized cell name',
      () {
        // reset_domains has a synthesized flop `$procdff$9` whose Q output is
        // the RTL reg `alarm_r` (net id 9). Selecting the flop must cross-probe
        // as `reset_domains.alarm_r` (kind: net) so WaveCrux leaf-matches the
        // waveform signal `alarm_r` — not `$procdff$9`, which the VCD lacks.
        const top = Module(
          name: 'reset_domains',
          attributes: <String, String>{'top': '1'},
          ports: <String, Port>{},
          cells: <String, Cell>{
            r'$procdff$9': Cell(
              name: r'$procdff$9',
              type: r'$procdff',
              parameters: <String, String>{},
              attributes: <String, String>{},
              portDirections: <String, PortDirection>{
                'D': PortDirection.input,
                'Q': PortDirection.output,
              },
              connections: <String, List<BitRef>>{
                'Q': <BitRef>[NetBit(9)],
              },
            ),
          },
          nets: <String, Net>{
            'alarm_r': Net(
              name: 'alarm_r',
              bits: <BitRef>[NetBit(9)],
              attributes: <String, String>{},
            ),
          },
        );
        const model = NetlistModel(
          creator: 'test',
          modules: <String, Module>{'reset_domains': top},
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(hierarchyTreeProvider.notifier).setModel(model);
        final tree = container.read(hierarchyTreeProvider);

        final resolved = resolveCxpSelection(
          element: const SelectedElement.cell(cellId: r'$procdff$9'),
          model: tree.model,
          scope: tree.selected,
        )!;
        expect(resolved.element.kind, ElementKind.net);
        expect(resolved.element.path, 'reset_domains.alarm_r');
        expect(resolved.element.path.split('.').last, 'alarm_r');
        expect(resolved.displayName, 'alarm_r');
      },
    );

    test(
      'A register whose Q net is MERGED with an output port emits the '
      'register-name alias, not the output-port alias',
      () {
        // reset_domains: `reg alarm_r; assign alarm = alarm_r;` with
        // `output wire alarm`. After proc + opt_clean the two nets fold into
        // ONE net (net id 14 in the real elaboration) carrying BOTH public
        // aliases `alarm` and `alarm_r`; the flop is the SYNTHETIC `$procdff$9`
        // cell (its own name matches neither alias). The user selected the
        // register, so the cross-probe must emit `alarm_r` — the INTERNAL reg
        // alias — NOT the coincidental output-port alias `alarm` (which
        // WaveCrux would highlight instead). `alarm` (the port) is declared
        // FIRST here so the test fails on plain first-match order and only
        // passes when the internal (non-port) alias is preferred.
        const top = Module(
          name: 'reset_domains',
          attributes: <String, String>{'top': '1'},
          ports: <String, Port>{
            'alarm': Port(
              name: 'alarm',
              direction: PortDirection.output,
              bits: [NetBit(14)],
            ),
          },
          cells: <String, Cell>{
            r'$procdff$9': Cell(
              name: r'$procdff$9',
              type: r'$dff',
              parameters: <String, String>{},
              attributes: <String, String>{},
              portDirections: <String, PortDirection>{
                'D': PortDirection.input,
                'Q': PortDirection.output,
              },
              connections: <String, List<BitRef>>{
                'Q': <BitRef>[NetBit(14)],
              },
            ),
          },
          nets: <String, Net>{
            // Output-port alias FIRST — the pre-refinement first-match pick.
            'alarm': Net(
              name: 'alarm',
              bits: <BitRef>[NetBit(14)],
              attributes: <String, String>{},
            ),
            'alarm_r': Net(
              name: 'alarm_r',
              bits: <BitRef>[NetBit(14)],
              attributes: <String, String>{},
            ),
          },
        );
        const model = NetlistModel(
          creator: 'test',
          modules: <String, Module>{'reset_domains': top},
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(hierarchyTreeProvider.notifier).setModel(model);
        final tree = container.read(hierarchyTreeProvider);

        final resolved = resolveCxpSelection(
          element: const SelectedElement.cell(cellId: r'$procdff$9'),
          model: tree.model,
          scope: tree.selected,
        )!;
        expect(resolved.element.kind, ElementKind.net);
        expect(resolved.element.path, 'reset_domains.alarm_r');
        expect(resolved.element.path.split('.').last, 'alarm_r');
        expect(resolved.displayName, 'alarm_r');
      },
    );

    test(
      'A PUBLIC-named flop whose name aliases the merged Q net emits its '
      'own name over the output-port alias',
      () {
        // Belt-and-braces for a Yosys flow that names the flop after its reg
        // (`\reg_r`): when the flop cell's own name is itself one of the Q-net
        // aliases, prefer it (rule 1) — still not the output-port alias `out`.
        const top = Module(
          name: 'top',
          attributes: <String, String>{'top': '1'},
          ports: <String, Port>{
            'out': Port(
              name: 'out',
              direction: PortDirection.output,
              bits: [NetBit(7)],
            ),
          },
          cells: <String, Cell>{
            'reg_r': Cell(
              name: 'reg_r',
              type: r'$dff',
              parameters: <String, String>{},
              attributes: <String, String>{},
              portDirections: <String, PortDirection>{
                'Q': PortDirection.output,
              },
              connections: <String, List<BitRef>>{
                'Q': <BitRef>[NetBit(7)],
              },
            ),
          },
          nets: <String, Net>{
            'out': Net(
              name: 'out',
              bits: <BitRef>[NetBit(7)],
              attributes: <String, String>{},
            ),
            'reg_r': Net(
              name: 'reg_r',
              bits: <BitRef>[NetBit(7)],
              attributes: <String, String>{},
            ),
          },
        );
        const model = NetlistModel(
          creator: 'test',
          modules: <String, Module>{'top': top},
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(hierarchyTreeProvider.notifier).setModel(model);
        final tree = container.read(hierarchyTreeProvider);

        final resolved = resolveCxpSelection(
          element: const SelectedElement.cell(cellId: 'reg_r'),
          model: tree.model,
          scope: tree.selected,
        )!;
        expect(resolved.element.path, 'top.reg_r');
        expect(resolved.displayName, 'reg_r');
      },
    );

    test(
      'A register whose Q net is synthetic/unnamed falls back to the '
      'instance name',
      () {
        // The flop's only Q net is a synthetic `$0\…` next-state shadow (no
        // source-declared name) — there is nothing waveform-matchable, so the
        // resolver keeps the instance-name form rather than emitting a `$` net.
        const top = Module(
          name: 'top',
          attributes: <String, String>{'top': '1'},
          ports: <String, Port>{},
          cells: <String, Cell>{
            r'$dff$3': Cell(
              name: r'$dff$3',
              type: r'$dff',
              parameters: <String, String>{},
              attributes: <String, String>{},
              portDirections: <String, PortDirection>{
                'Q': PortDirection.output,
              },
              connections: <String, List<BitRef>>{
                'Q': <BitRef>[NetBit(11)],
              },
            ),
          },
          nets: <String, Net>{
            r'$0\q[0:0]': Net(
              name: r'$0\q[0:0]',
              bits: <BitRef>[NetBit(11)],
              attributes: <String, String>{},
              hideName: true,
            ),
          },
        );
        const model = NetlistModel(
          creator: 'test',
          modules: <String, Module>{'top': top},
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(hierarchyTreeProvider.notifier).setModel(model);
        final tree = container.read(hierarchyTreeProvider);

        final resolved = resolveCxpSelection(
          element: const SelectedElement.cell(cellId: r'$dff$3'),
          model: tree.model,
          scope: tree.selected,
        )!;
        expect(resolved.element.kind, ElementKind.instance);
        expect(resolved.element.path, r'top.$dff$3');
      },
    );

    test('a cell port resolves to a clean dot-joined port path', () {
      final resolved = resolveCxpSelection(
        element: const SelectedElement.port(
          cellId: 'u_cpu',
          portId: 'u_cpu:clk',
          portName: 'clk',
        ),
        model: _loadedTree().model,
        scope: _loadedTree().scope,
      )!;
      expect(resolved.element.kind, ElementKind.port);
      expect(resolved.element.path, 'top.u_cpu.clk');
      expect(resolved.element.path, isNot(contains(':port:')));
      expect(resolved.element.path.split('.').last, 'clk');
      expect(resolved.displayName, 'clk');
    });

    test('a boundary port emits a clean <scope>.<port> path — no :port:', () {
      // The cross-probe identity bug: a top-level `output reg state` was sent
      // as `fsm_lock:port:state`, which WaveCrux's dot-split leaf-matcher can't
      // parse. It must now be a clean dot-joined name whose leaf is the port.
      final resolved = resolveCxpSelection(
        element: const SelectedElement.boundaryPort(
          portId: 'top:rst_n',
          portName: 'rst_n',
        ),
        model: _loadedTree().model,
        scope: _loadedTree().scope,
      )!;
      expect(resolved.element.kind, ElementKind.port);
      expect(resolved.element.path, 'top.rst_n');
      expect(resolved.element.path, isNot(contains(':port:')));
      expect(resolved.element.path.split('.').last, 'rst_n');
      expect(resolved.displayName, 'rst_n');
    });

    test(
      'a wire on an ANONYMOUS net falls back to the net_ display name',
      () {
        // _model() declares no named nets, so netId 7 belongs to no named
        // net — the resolver falls back to the opaque `:net:` form.
        final resolved = resolveCxpSelection(
          element: const SelectedElement.wire(netId: 7, edgeId: 'e_7_0'),
          model: _loadedTree().model,
          scope: _loadedTree().scope,
        )!;
        expect(resolved.element.kind, ElementKind.net);
        expect(resolved.displayName, 'net_7');
        expect(resolved.element.path, contains(':net:'));
      },
    );
  });

  group('wire identity carries the human net NAME (cross-probe fix)', () {
    // A multi-bit bus mirroring cdc_capture's `reg [7:0] sample_a`: distinct
    // Yosys net ids per bit, declared under one named net. Grounded against a
    // real `yosys` elaboration of cdc_capture.v, whose `sample_a` carries
    // netIds 15..22 — see the yosys-gated test below.
    ({NetlistModel? model, HierarchyNode? scope}) busTree() {
      const top = Module(
        name: 'cdc_capture',
        attributes: <String, String>{'top': '1'},
        ports: {},
        cells: {},
        nets: <String, Net>{
          'sample_a': Net(
            name: 'sample_a',
            bits: [
              NetBit(15),
              NetBit(16),
              NetBit(17),
              NetBit(18),
            ],
            attributes: {},
          ),
        },
      );
      const model = NetlistModel(
        creator: 'test',
        modules: <String, Module>{'cdc_capture': top},
      );
      return (model: model, scope: HierarchyNode.rootOf(model));
    }

    test('emits <scope>.<netName>, kind net — no opaque :net: edge id', () {
      final tree = busTree();
      // Select a NON-zero bit of the bus to prove the reverse-resolution
      // scans all bits, not just bit 0.
      final resolved = resolveCxpSelection(
        element: const SelectedElement.wire(netId: 17, edgeId: 'e_17_10'),
        model: tree.model,
        scope: tree.scope,
      )!;
      expect(resolved.element.kind, ElementKind.net);
      expect(resolved.element.path, 'cdc_capture.sample_a');
      expect(resolved.element.path, contains('sample_a'));
      expect(resolved.element.path, isNot(contains(':net:')));
      expect(resolved.displayName, 'sample_a');
    });

    test('a source-named net wins over a synthetic hide_name shadow net', () {
      // Yosys emits a `$0\sample_a[7:0]` next-state shadow net over the same
      // bits; the user-facing `sample_a` (hide_name == 0) must win.
      const top = Module(
        name: 'cdc_capture',
        attributes: <String, String>{'top': '1'},
        ports: {},
        cells: {},
        nets: <String, Net>{
          r'$0\sample_a[7:0]': Net(
            name: r'$0\sample_a[7:0]',
            bits: [NetBit(15)],
            attributes: {},
            hideName: true,
          ),
          'sample_a': Net(
            name: 'sample_a',
            bits: [NetBit(15)],
            attributes: {},
          ),
        },
      );
      const model = NetlistModel(
        creator: 'test',
        modules: <String, Module>{'cdc_capture': top},
      );
      final resolved = resolveCxpSelection(
        element: const SelectedElement.wire(netId: 15, edgeId: 'e_15_0'),
        model: model,
        scope: HierarchyNode.rootOf(model),
      )!;
      expect(resolved.element.path, 'cdc_capture.sample_a');
      expect(resolved.displayName, 'sample_a');
    });
  });

  group('real cdc_capture elaboration (yosys-gated)', () {
    test(
      'selecting sample_a emits cdc_capture.sample_a, kind net',
      () async {
        final probe = await YosysAvailabilityService(
          runner: const DefaultProcessRunner(),
        ).probe();
        if (!probe.isAvailable) {
          markTestSkipped('yosys not on PATH — skipping real elaboration');
          return;
        }
        final result = await YosysRunner().run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile(_cdcCaptureVPath)],
            topModule: 'cdc_capture',
          ),
        );
        expect(result, isA<YosysRunSuccess>());
        final model = const YosysJsonParser().parse(
          (result as YosysRunSuccess).rawJson,
        );
        final scope = HierarchyNode.rootOf(model)!;
        final sampleA = scope.resolve(model)!.nets['sample_a']!;
        // Reverse the grounded fact: sample_a is a real 8-bit bus.
        expect(sampleA.width, greaterThan(1));
        final firstBit = sampleA.bits.whereType<NetBit>().first.netId;
        final resolved = resolveCxpSelection(
          element: SelectedElement.wire(
            netId: firstBit,
            edgeId: 'e_${firstBit}_0',
          ),
          model: model,
          scope: scope,
        )!;
        expect(resolved.element.kind, ElementKind.net);
        expect(resolved.element.path, 'cdc_capture.sample_a');
        expect(resolved.element.path, isNot(contains(':net:')));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('real fsm_lock elaboration (yosys-gated)', () {
    test(
      'cross-probing the `state` boundary port emits fsm_lock.state, kind port',
      () async {
        final probe = await YosysAvailabilityService(
          runner: const DefaultProcessRunner(),
        ).probe();
        if (!probe.isAvailable) {
          markTestSkipped('yosys not on PATH — skipping real elaboration');
          return;
        }
        final result = await YosysRunner().run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile(_fsmLockVPath)],
            topModule: 'fsm_lock',
          ),
        );
        expect(result, isA<YosysRunSuccess>());
        final model = const YosysJsonParser().parse(
          (result as YosysRunSuccess).rawJson,
        );
        final scope = HierarchyNode.rootOf(model)!;
        // Ground the fact the bug hinged on: `state` really is a top-level
        // boundary port (an `output reg`), not a cell port or internal net.
        expect(model.topModule!.name, 'fsm_lock');
        expect(model.topModule!.ports.containsKey('state'), isTrue);
        final resolved = resolveCxpSelection(
          element: const SelectedElement.boundaryPort(
            portId: 'fsm_lock:state',
            portName: 'state',
          ),
          model: model,
          scope: scope,
        )!;
        expect(resolved.element.kind, ElementKind.port);
        expect(resolved.element.path, 'fsm_lock.state');
        expect(resolved.element.path, isNot(contains(':port:')));
        // The WaveCrux dot-split leaf that previously failed now yields `state`.
        expect(resolved.element.path.split('.').last, 'state');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('real reset_domains elaboration (yosys-gated)', () {
    test(
      'cross-probing the alarm_r register emits reset_domains.alarm_r (the '
      'internal reg alias), NOT the output-port alias alarm',
      () async {
        final probe = await YosysAvailabilityService(
          runner: const DefaultProcessRunner(),
        ).probe();
        if (!probe.isAvailable) {
          markTestSkipped('yosys not on PATH — skipping real elaboration');
          return;
        }
        final result = await YosysRunner().run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile(_resetDomainsVPath)],
            topModule: 'reset_domains',
          ),
        );
        expect(result, isA<YosysRunSuccess>());
        final model = const YosysJsonParser().parse(
          (result as YosysRunSuccess).rawJson,
        );
        final scope = HierarchyNode.rootOf(model)!;
        final module = scope.resolve(model)!;

        // Grounded fact: opt_clean folds `assign alarm = alarm_r` so BOTH
        // public net aliases carry the same bit, and `alarm` is a module port.
        final alarmR = module.nets['alarm_r']!;
        final netId = alarmR.bits.whereType<NetBit>().first.netId;
        expect(
          module.nets['alarm']!.bits.whereType<NetBit>().first.netId,
          netId,
          reason: 'alarm and alarm_r must be aliases of the same merged net',
        );
        expect(module.ports.containsKey('alarm'), isTrue);

        // Find the synthesized flop driving that net (its name is a synthetic
        // `$procdff$…`, so we locate it by its Q output, not by name) and
        // cross-probe it — the exact "select the register" gesture.
        final flopId = module.cells.entries.firstWhere((e) {
          final t = e.value.type.toLowerCase();
          if (!t.contains('dff') && !t.contains('dlatch')) return false;
          final q = e.value.connections['Q'];
          return q != null &&
              q.whereType<NetBit>().any((b) => b.netId == netId);
        }).key;

        final resolved = resolveCxpSelection(
          element: SelectedElement.cell(cellId: flopId),
          model: model,
          scope: scope,
        )!;
        expect(resolved.element.kind, ElementKind.net);
        expect(resolved.element.path, 'reset_domains.alarm_r');
        expect(resolved.element.path.split('.').last, 'alarm_r');
        expect(resolved.displayName, 'alarm_r');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('toNotifySelection', () {
    test('carries the element, display name, and scope-path metadata', () {
      final resolved = resolveCxpSelection(
        element: const SelectedElement.cell(cellId: 'u_cpu'),
        model: _loadedTree().model,
        scope: _loadedTree().scope,
      )!;

      final message = resolved.toNotifySelection();
      expect(message.kind, CxpMessageKind.notifySelection);
      expect(message.elements, <ElementId>[resolved.element]);
      expect(message.displayName, 'u_cpu');
      expect(message.metadata['netcrux.scope_path'], resolved.scopePath);
    });
  });

  group('kind and label helpers', () {
    test('cxpElementKindFor covers every SelectedElement variant', () {
      expect(
        cxpElementKindFor(const SelectedElement.none()),
        ElementKind.instance,
      );
      expect(
        cxpElementKindFor(const SelectedElement.cell(cellId: 'c')),
        ElementKind.instance,
      );
      expect(
        cxpElementKindFor(
          const SelectedElement.port(cellId: 'c', portId: 'c:p', portName: 'p'),
        ),
        ElementKind.port,
      );
      expect(
        cxpElementKindFor(
          const SelectedElement.boundaryPort(portId: 'top:p', portName: 'p'),
        ),
        ElementKind.port,
      );
      expect(
        cxpElementKindFor(const SelectedElement.wire(netId: 1, edgeId: 'e')),
        ElementKind.net,
      );
    });

    test('cxpDisplayNameFor covers every SelectedElement variant', () {
      expect(cxpDisplayNameFor(const SelectedElement.none()), isNull);
      expect(cxpDisplayNameFor(const SelectedElement.cell(cellId: 'c')), 'c');
      expect(
        cxpDisplayNameFor(
          const SelectedElement.port(cellId: 'c', portId: 'c:p', portName: 'p'),
        ),
        'p',
      );
      expect(
        cxpDisplayNameFor(
          const SelectedElement.boundaryPort(portId: 'top:p', portName: 'p'),
        ),
        'p',
      );
      expect(
        cxpDisplayNameFor(const SelectedElement.wire(netId: 3, edgeId: 'e')),
        'net_3',
      );
    });
  });
}
