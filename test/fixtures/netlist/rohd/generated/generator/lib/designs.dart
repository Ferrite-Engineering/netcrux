// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Small ROHD designs whose netlists exercise the extensions ROHD's netlist
// writer adds to Yosys JSON: structured ports, struct pack and unpack cells,
// arrays, hierarchy, sequential and combinational blocks, and source traces.

import 'package:rohd/rohd.dart';

/// A one-beat payload: sixteen data bits and a valid flag.
class Sample extends LogicStructure {
  Sample({String name = 'sample'})
    : super([Logic(name: 'data', width: 16), Logic(name: 'valid')], name: name);

  Logic get data => elements[0];
  Logic get valid => elements[1];

  @override
  Sample clone({String? name}) => Sample(name: name ?? this.name);
}

/// A structure nested inside another: a [Sample] and a four-bit tag.
class TaggedSample extends LogicStructure {
  TaggedSample({String name = 'tagged'})
    : super([Sample(name: 'beat'), Logic(name: 'tag', width: 4)], name: name);

  Sample get beat => elements[0] as Sample;
  Logic get tag => elements[1];

  @override
  TaggedSample clone({String? name}) => TaggedSample(name: name ?? this.name);
}

/// Registers a [Sample] on a clock edge and doubles its data when it is
/// valid: struct input and output ports, field reads (`$struct_unpack`),
/// a struct built from fields (`$struct_pack`), a flip-flop and a
/// combinational block.
class SamplePipeline extends Module {
  SamplePipeline(Logic clk, Logic reset, Sample sampleIn)
    : super(name: 'sample_pipeline') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    final inbound = addTypedInput('sample_in', sampleIn);
    final outbound = addTypedOutput('sample_out', sampleIn.clone);

    final scaled = Logic(name: 'scaled', width: 16);
    Combinational([
      If(
        inbound.valid,
        then: [scaled < inbound.data << 1],
        orElse: [scaled < inbound.data],
      ),
    ]);

    final staged = Sample(name: 'staged');
    Sequential(
      clk,
      reset: reset,
      [
        staged.data < scaled,
        staged.valid < inbound.valid,
      ],
      resetValues: {
        staged.data: 0,
        staged.valid: 0,
      },
    );
    outbound <= staged;
  }
}

/// Reads the fields of a nested structure and rebuilds the outer one.
class TaggedRelay extends Module {
  TaggedRelay(TaggedSample item) : super(name: 'tagged_relay') {
    final inbound = addTypedInput('item', item);
    final outbound = addTypedOutput('relayed', item.clone);
    final next = TaggedSample(name: 'next');
    next.beat.data <= inbound.beat.data;
    next.beat.valid <= inbound.beat.valid;
    next.tag <= inbound.tag + 1;
    outbound <= next;
  }
}

/// Sums the lanes of an array port and selects one lane by index.
class LaneReducer extends Module {
  LaneReducer(LogicArray lanes, Logic select) : super(name: 'lane_reducer') {
    lanes = addInputArray(
      'lanes',
      lanes,
      dimensions: [4],
      elementWidth: 8,
    );
    select = addInput('select', select, width: 2);
    final total = addOutput('total', width: 10);
    final picked = addOutput('picked', width: 8);
    final reversed = addOutputArray(
      'reversed',
      dimensions: [4],
      elementWidth: 8,
    );

    Logic sum = Const(0, width: 10);
    for (final lane in lanes.elements) {
      sum = sum + lane.zeroExtend(10);
    }
    total <= sum;
    picked <= lanes.elements.selectIndex(select);
    for (var i = 0; i < 4; i++) {
      reversed.elements[i] <= lanes.elements[3 - i];
    }
  }
}

enum _Phase { idle, load, run }

/// A three-state controller built from ROHD's state machine.
class PhaseController extends Module {
  PhaseController(Logic clk, Logic reset, Logic start, Logic done)
    : super(name: 'phase_controller') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    start = addInput('start', start);
    done = addInput('done', done);
    final loading = addOutput('loading');
    final running = addOutput('running');

    final machine = FiniteStateMachine<_Phase>(
      clk,
      reset,
      _Phase.idle,
      [
        State(
          _Phase.idle,
          events: {start: _Phase.load},
          actions: [loading < 0, running < 0],
        ),
        State(
          _Phase.load,
          events: {Const(1): _Phase.run},
          actions: [loading < 1, running < 0],
        ),
        State(
          _Phase.run,
          events: {done: _Phase.idle},
          actions: [loading < 0, running < 1],
        ),
      ],
    );
    // Keeps the state machine's own signals in the module.
    addOutput('state', width: machine.currentState.width) <=
        machine.currentState;
  }
}

/// Three levels of hierarchy: a pipeline, a relay, a reducer and a
/// controller under one top.
class DemoTop extends Module {
  DemoTop(Logic clk, Logic reset, Logic start) : super(name: 'demo_top') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    start = addInput('start', start);
    final data = addInput('data', Logic(width: 16), width: 16);
    final valid = addInput('valid', Logic());
    final laneBus = addInput('lane_bus', Logic(width: 32), width: 32);
    final laneSelect = addInput('lane_select', Logic(width: 2), width: 2);

    final feed = Sample(name: 'feed');
    feed.data <= data;
    feed.valid <= valid;
    final pipeline = SamplePipeline(clk, reset, feed);

    final tagged = TaggedSample(name: 'tagged_feed');
    tagged.beat <= pipeline.output('sample_out');
    tagged.tag <= Const(3, width: 4);
    final relay = TaggedRelay(tagged);

    final lanes = LogicArray([4], 8, name: 'lane_array');
    for (var i = 0; i < 4; i++) {
      lanes.elements[i] <= laneBus.getRange(i * 8, i * 8 + 8);
    }
    final reducer = LaneReducer(lanes, laneSelect);

    final controller = PhaseController(clk, reset, start, valid);

    addOutput('relayed', width: tagged.width) <= relay.output('relayed');
    addOutput('total', width: 10) <= reducer.output('total');
    addOutput('running') <= controller.output('running');
    addOutput('loading') <= controller.output('loading');
  }
}
