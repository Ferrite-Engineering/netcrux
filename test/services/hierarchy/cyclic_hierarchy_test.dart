// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_panel.dart';
import 'package:netcrux/services/search/design_search_service.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// A module that instantiates itself. Yosys never emits this, but NetCrux
/// opens netlist JSON directly (the web viewer loads whatever URL it is
/// given), so the file is the input, not the synthesis tool.
const String _selfInstantiating =
    '{"modules":{"top":{"attributes":{"top":"1"},'
    '"cells":{"u_self":{"type":"top"}}}}}';

/// `a` instantiates `b`, which instantiates `a` — the same cycle two steps
/// long — plus a sibling that is not part of it.
const String _twoStepCycle =
    '{"modules":{'
    '"a":{"attributes":{"top":"1"},'
    '"cells":{"u_b":{"type":"b"},"u_leaf":{"type":"leaf"}}},'
    '"b":{"cells":{"u_a":{"type":"a"}}},'
    '"leaf":{"cells":{}}}}';

NetlistModel _parse(String json) => const YosysJsonParser().parse(json);

/// [length] modules, each instantiating the next once: a hierarchy as deep
/// as the file says, with no cycle for the recursion check to stop.
String _chainOfModules(int length) => _modulesJson(
  length,
  (i) => i + 1 < length ? '"u":{"type":"m${i + 1}"}' : '',
);

/// [levels] modules, each instantiating the next twice: 2^levels scopes
/// from a file a few kilobytes long.
String _doublingDag(int levels) => _modulesJson(
  levels,
  (i) =>
      i + 1 < levels ? '"a":{"type":"m${i + 1}"},"b":{"type":"m${i + 1}"}' : '',
);

/// A netlist of modules `m0` (the top) to `m<count - 1>`, where [cells]
/// gives module `m<i>`'s cell map body.
String _modulesJson(int count, String Function(int i) cells) {
  final modules = <String>[];
  for (var i = 0; i < count; i++) {
    final top = i == 0 ? '"attributes":{"top":"1"},' : '';
    modules.add('"m$i":{$top"cells":{${cells(i)}}}');
  }
  return '{"modules":{${modules.join(',')}}}';
}

/// The tree state the panel builds from: [model] loaded (root expanded, as
/// `setModel` leaves it) and [filter] typed into the filter box.
HierarchyTreeState _stateFor(NetlistModel model, {String filter = ''}) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(hierarchyTreeProvider.notifier)
    ..setModel(model)
    ..setFilterText(filter);
  return container.read(hierarchyTreeProvider);
}

void main() {
  group('a cyclic hierarchy', () {
    test('a search that matches nothing terminates', () {
      final model = _parse(_selfInstantiating);
      final hits = const DesignSearchService().search(
        model: model,
        query: 'no_such_thing',
      );
      expect(hits, isEmpty);
    });

    test('a search finds the recursive instance once, as a cell of its '
        'parent', () {
      final model = _parse(_selfInstantiating);
      final hits = const DesignSearchService().search(
        model: model,
        query: 'u_self',
      );
      expect(hits, hasLength(1));
      expect(hits.single.scope, 'top');
    });

    test('a two-step cycle is searched once around', () {
      final model = _parse(_twoStepCycle);
      final hits = const DesignSearchService().search(
        model: model,
        query: 'u_',
      );
      // a: u_b, u_leaf; a.u_b (module b): u_a. Descending into a.u_b.u_a
      // would re-enter `a`, which is already on the path.
      expect(hits.map((h) => '${h.scope}/${h.name}'), <String>[
        'a/u_b',
        'a/u_leaf',
        'a.u_b/u_a',
      ]);
    });

    test('a hierarchy filter that matches nothing terminates', () {
      final model = _parse(_selfInstantiating);
      final rows = buildVisibleRows(
        model: model,
        state: _stateFor(model, filter: 'no_such_thing'),
      );
      expect(rows, isEmpty);
    });

    test('a hierarchy filter that matches every lap terminates, and the '
        'recursive instance is a leaf', () {
      final model = _parse(_selfInstantiating);
      // `top` is the module name of the root AND of every lap of the cycle.
      final rows = buildVisibleRows(
        model: model,
        state: _stateFor(model, filter: 'top'),
      );
      expect(rows.map((r) => r.instanceName), <String>['top', 'u_self']);
      expect(rows.last.hasChildren, isFalse);
    });

    test('a chain of 100,000 modules, each inside the last, does not '
        'exhaust the stack', () {
      final model = _parse(_chainOfModules(100000));
      final stopwatch = Stopwatch()..start();
      expect(
        const DesignSearchService().search(model: model, query: 'nope'),
        isEmpty,
      );
      expect(
        buildVisibleRows(
          model: model,
          state: _stateFor(model, filter: 'nope'),
        ),
        isEmpty,
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
    });

    test('a hierarchy that doubles at every level is walked to a bound, '
        'not to 2^30 scopes', () {
      final model = _parse(_doublingDag(30));
      final stopwatch = Stopwatch()..start();
      expect(
        const DesignSearchService().search(model: model, query: 'nope'),
        isEmpty,
      );
      expect(
        buildVisibleRows(
          model: model,
          state: _stateFor(model, filter: 'nope'),
        ),
        isEmpty,
      );
      // A match deep in the tree is still found within the bound.
      final hits = const DesignSearchService().search(
        model: model,
        query: 'a',
        maxResults: 40,
      );
      expect(hits, hasLength(40));
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
    });

    test('an unfiltered tree shows the recursive instance as a leaf', () {
      final model = _parse(_twoStepCycle);
      final state = _stateFor(model);
      final rows = buildVisibleRows(model: model, state: state);
      expect(rows.map((r) => r.instanceName), <String>['a', 'u_b', 'u_leaf']);
      expect(rows[1].hasChildren, isTrue, reason: 'b is not on the path yet');
    });
  });
}
