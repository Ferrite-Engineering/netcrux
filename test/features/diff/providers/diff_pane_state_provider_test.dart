// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/netlist_diff_service.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_request.dart';
import 'package:netcrux/features/diff/providers/diff_pane_state_provider.dart';
import 'package:netcrux/services/diff/netlist_diff_service_provider.dart';

class _StubService implements NetlistDiffService {
  _StubService(this._fixed);

  final NetlistDiff _fixed;

  @override
  Future<NetlistDiff> compare(NetlistDiffRequest request) async => _fixed;

  @override
  Stream<void> get diffsInvalidated => const Stream<void>.empty();
}

NetlistDiff _seed() => NetlistDiff(
  baselineNetlist: const NetlistRef(identifier: 'a'),
  comparisonNetlist: const NetlistRef(identifier: 'b'),
  generatedAt: DateTime.utc(2026, 5, 25),
  elementChanges: const <ElementChange>[
    ElementChange(
      kind: ElementChangeKind.added,
      elementKind: NetlistDiffElementKind.instance,
      elementId: ElementId(kind: ElementKind.instance, path: 'top.a'),
    ),
    ElementChange(
      kind: ElementChangeKind.removed,
      elementKind: NetlistDiffElementKind.net,
      elementId: ElementId(kind: ElementKind.net, path: 'top:net:n1'),
    ),
    ElementChange(
      kind: ElementChangeKind.modified,
      elementKind: NetlistDiffElementKind.port,
      elementId: ElementId(kind: ElementKind.port, path: 'top.in'),
    ),
  ],
);

void main() {
  ProviderContainer makeContainer(NetlistDiff seeded) {
    return ProviderContainer(
      overrides: <Override>[
        netlistDiffServiceProvider.overrideWithValue(_StubService(seeded)),
      ],
    );
  }

  test('build returns empty state', () {
    final c = makeContainer(NetlistDiff.empty());
    addTearDown(c.dispose);
    expect(c.read(diffPaneStateProvider), equals(DiffPaneState.empty));
  });

  test('setRequest publishes the diff and auto-selects index 0', () async {
    final c = makeContainer(_seed());
    addTearDown(c.dispose);
    await c
        .read(diffPaneStateProvider.notifier)
        .setRequest(
          const NetlistDiffRequest(
            baselineNetlist: NetlistRef(identifier: 'a'),
            comparisonNetlist: NetlistRef(identifier: 'b'),
          ),
        );
    final state = c.read(diffPaneStateProvider);
    expect(state.hasActiveDiff, isTrue);
    expect(state.activeDiff!.elementChanges, hasLength(3));
    expect(state.selectedChangeIndex, 0);
    expect(state.isComputing, isFalse);
  });

  test('clearRequest resets to empty', () async {
    final c = makeContainer(_seed());
    addTearDown(c.dispose);
    await c
        .read(diffPaneStateProvider.notifier)
        .setRequest(
          const NetlistDiffRequest(
            baselineNetlist: NetlistRef(identifier: 'a'),
            comparisonNetlist: NetlistRef(identifier: 'b'),
          ),
        );
    c.read(diffPaneStateProvider.notifier).clearRequest();
    expect(c.read(diffPaneStateProvider), equals(DiffPaneState.empty));
  });

  test('toggleKindFilter accumulates and filtered list shrinks', () async {
    final c = makeContainer(_seed());
    addTearDown(c.dispose);
    final notifier = c.read(diffPaneStateProvider.notifier);
    await notifier.setRequest(
      const NetlistDiffRequest(
        baselineNetlist: NetlistRef(identifier: 'a'),
        comparisonNetlist: NetlistRef(identifier: 'b'),
      ),
    );
    notifier.toggleKindFilter(ElementChangeKind.added);
    final state = c.read(diffPaneStateProvider);
    expect(state.filteredKinds, contains(ElementChangeKind.added));
    expect(state.filteredChanges, hasLength(1));
    expect(state.filteredChanges.first.kind, ElementChangeKind.added);
  });

  test('toggleElementKindFilter restricts to one element kind', () async {
    final c = makeContainer(_seed());
    addTearDown(c.dispose);
    final notifier = c.read(diffPaneStateProvider.notifier);
    await notifier.setRequest(
      const NetlistDiffRequest(
        baselineNetlist: NetlistRef(identifier: 'a'),
        comparisonNetlist: NetlistRef(identifier: 'b'),
      ),
    );
    notifier.toggleElementKindFilter(NetlistDiffElementKind.net);
    final filtered = c.read(diffPaneStateProvider).filteredChanges;
    expect(filtered, hasLength(1));
    expect(filtered.first.elementKind, NetlistDiffElementKind.net);
  });

  test('selectNext / selectPrevious wrap around', () async {
    final c = makeContainer(_seed());
    addTearDown(c.dispose);
    final notifier = c.read(diffPaneStateProvider.notifier);
    await notifier.setRequest(
      const NetlistDiffRequest(
        baselineNetlist: NetlistRef(identifier: 'a'),
        comparisonNetlist: NetlistRef(identifier: 'b'),
      ),
    );
    // Initial index after setRequest is 0.
    expect(c.read(diffPaneStateProvider).selectedChangeIndex, 0);
    notifier.selectNext();
    expect(c.read(diffPaneStateProvider).selectedChangeIndex, 1);
    notifier.selectNext();
    expect(c.read(diffPaneStateProvider).selectedChangeIndex, 2);
    notifier.selectNext();
    // Wraps.
    expect(c.read(diffPaneStateProvider).selectedChangeIndex, 0);
    notifier.selectPrevious();
    expect(c.read(diffPaneStateProvider).selectedChangeIndex, 2);
  });

  test('toggleOverlay flips overlayVisible', () {
    final c = makeContainer(NetlistDiff.empty());
    addTearDown(c.dispose);
    expect(c.read(diffPaneStateProvider).overlayVisible, isTrue);
    c.read(diffPaneStateProvider.notifier).toggleOverlay();
    expect(c.read(diffPaneStateProvider).overlayVisible, isFalse);
  });

  test('activeDiffProvider mirrors the notifier state', () async {
    final c = makeContainer(_seed());
    addTearDown(c.dispose);
    expect(c.read(activeDiffProvider), isNull);
    await c
        .read(diffPaneStateProvider.notifier)
        .setRequest(
          const NetlistDiffRequest(
            baselineNetlist: NetlistRef(identifier: 'a'),
            comparisonNetlist: NetlistRef(identifier: 'b'),
          ),
        );
    expect(c.read(activeDiffProvider), isNotNull);
    expect(c.read(activeDiffProvider)!.elementChanges, hasLength(3));
  });

  test('filteredChanges lists the groups in display order, so navigation '
      'walks the list as shown', () {
    final diff = NetlistDiff(
      baselineNetlist: const NetlistRef(identifier: 'a'),
      comparisonNetlist: const NetlistRef(identifier: 'b'),
      generatedAt: DateTime.utc(2026, 10, 5),
      elementChanges: const <ElementChange>[
        ElementChange(
          kind: ElementChangeKind.modified,
          elementKind: NetlistDiffElementKind.module,
          elementId: ElementId(kind: ElementKind.scope, path: 'top:module'),
        ),
        ElementChange(
          kind: ElementChangeKind.unchanged,
          elementKind: NetlistDiffElementKind.instance,
          elementId: ElementId(kind: ElementKind.instance, path: 'top.u:cell'),
        ),
        ElementChange(
          kind: ElementChangeKind.removed,
          elementKind: NetlistDiffElementKind.instance,
          elementId: ElementId(kind: ElementKind.instance, path: 'top.r:cell'),
        ),
        ElementChange(
          kind: ElementChangeKind.added,
          elementKind: NetlistDiffElementKind.net,
          elementId: ElementId(kind: ElementKind.net, path: 'top:net:a'),
        ),
        ElementChange(
          kind: ElementChangeKind.removed,
          elementKind: NetlistDiffElementKind.net,
          elementId: ElementId(kind: ElementKind.net, path: 'top:net:r'),
        ),
      ],
    );
    final state = DiffPaneState(activeDiff: diff);
    expect(
      state.filteredChanges.map((c) => c.elementId.path),
      <String>[
        'top:net:a',
        'top.r:cell',
        'top:net:r',
        'top:module',
        'top.u:cell',
      ],
    );
  });
}
