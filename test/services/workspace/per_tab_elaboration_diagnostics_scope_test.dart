// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Two-tab isolation contract for the elaboration-diagnostics providers, using
// the real production container topology: a root container plus per-tab
// children built from `netcruxTabOverridesFactory` (exactly how `bootstrap`
// composes them).
//
// The stderr holder and the severity filter were re-bound per tab, but the two
// *derived* views (`elaborationDiagnosticsProvider`,
// `filteredElaborationDiagnosticsProvider`) were not, so a tab-scoped read
// hoisted them to the ROOT container where their `watch` resolved ROOT's
// always-empty stderr: the tab diagnostics drawer showed no Yosys warnings
// after a successful elaboration, and the severity chips filtered a different
// instance than the one they rendered from.

import 'package:crux_workspace/crux_workspace.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';

const _warningStderr =
    'Warning: Wire top.\\unused_sig is used but has no driver.\n';
const _errorStderr = 'ERROR: syntax error in top.v line 12\n';

void main() {
  late ProviderContainer root;
  late TabContainerManager manager;

  setUp(() {
    root = ProviderContainer();
    manager = TabContainerManager(
      rootContainer: root,
      overridesFactory: netcruxTabOverridesFactory,
    );
  });

  tearDown(() {
    manager.dispose();
    root.dispose();
  });

  test('parsed diagnostics resolve the tab that elaborated, not root', () {
    final tabA = manager.containerFor(TabId.generate());
    final tabB = manager.containerFor(TabId.generate());

    tabA.read(elaborationStderrProvider.notifier).set(_warningStderr);

    expect(
      tabA.read(elaborationDiagnosticsProvider),
      isNotEmpty,
      reason: 'tab A must parse its own stderr, not the empty root',
    );
    expect(
      tabB.read(elaborationDiagnosticsProvider),
      isEmpty,
      reason: 'a tab that has not elaborated must show no diagnostics',
    );
    expect(
      root.read(elaborationDiagnosticsProvider),
      isEmpty,
      reason: 'tab state must not bleed up to root',
    );
  });

  test('the severity filter narrows the same tab it renders from', () {
    final tabA = manager.containerFor(TabId.generate());
    final tabB = manager.containerFor(TabId.generate());

    tabA
        .read(elaborationStderrProvider.notifier)
        .set('$_errorStderr$_warningStderr');
    final unfiltered = tabA.read(filteredElaborationDiagnosticsProvider);
    expect(unfiltered.length, greaterThan(1));

    // Drop warnings in tab A only.
    tabA
        .read(elaborationDiagnosticFilterProvider.notifier)
        .toggle(YosysDiagnosticSeverity.warning);

    final filtered = tabA.read(filteredElaborationDiagnosticsProvider);
    expect(
      filtered.length,
      lessThan(unfiltered.length),
      reason: "toggling a severity must narrow this tab's own list",
    );
    expect(
      filtered.every((d) => d.severity != YosysDiagnosticSeverity.warning),
      isTrue,
    );

    expect(
      tabB.read(elaborationDiagnosticFilterProvider),
      hasLength(YosysDiagnosticSeverity.values.length),
      reason: 'the filter must not bleed into a sibling tab',
    );
  });

  test('derived diagnostics views are distinct instances per tab', () {
    final tabA = manager.containerFor(TabId.generate());
    final tabB = manager.containerFor(TabId.generate());

    tabA.read(elaborationStderrProvider.notifier).set(_warningStderr);
    tabB.read(elaborationStderrProvider.notifier).set(_errorStderr);

    final a = tabA.read(filteredElaborationDiagnosticsProvider);
    final b = tabB.read(filteredElaborationDiagnosticsProvider);
    expect(a, isNotEmpty);
    expect(b, isNotEmpty);
    expect(
      a.first.severity == b.first.severity,
      isFalse,
      reason: 'each tab parses its own stderr',
    );
  });
}
