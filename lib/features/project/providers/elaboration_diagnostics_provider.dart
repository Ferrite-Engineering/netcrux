// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/services/yosys/yosys_diagnostic_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'elaboration_diagnostics_provider.g.dart';

/// Last-known Yosys stderr text. Populated by the elaboration
/// pipeline when a run completes (success *or* failure — Yosys
/// emits warnings to stderr even on successful runs) so the
/// diagnostics drawer can render the parsed [YosysDiagnostic] list
/// against the current state.
///
/// Empty string when no run has happened yet.
@Riverpod(keepAlive: true)
class ElaborationStderr extends _$ElaborationStderr {
  @override
  String build() => '';

  /// Replaces the stored stderr verbatim. Called by the elaboration
  /// pipeline at the end of every run.
  void set(String stderr) {
    if (state == stderr) return;
    state = stderr;
  }

  /// Clears the stored stderr — used by tests and by "Close
  /// Project" so a fresh project doesn't inherit the previous run's
  /// diagnostics.
  void clear() {
    if (state.isEmpty) return;
    state = '';
  }
}

/// Lines a Pro feature adds to the tab's Diagnostics, ahead of the
/// elaboration's own: each one a `Warning: message` line, or a
/// `path:line: Warning: message` line that names where in a file the
/// problem is, the forms the drawer parses.
///
/// The open-core build has none. The Pro overlay overrides this per tab, so
/// it can describe the tab's own design (the symbol libraries it reads and
/// how their symbols match the design's cells). A manual provider, so the
/// overlay overrides it without the code generator.
final overlayDiagnosticLinesProvider = Provider<List<String>>(
  (ref) => const <String>[],
  name: 'overlayDiagnosticLinesProvider',
);

/// Parsed [YosysDiagnostic] list for the current elaboration's
/// stderr, after the lines [overlayDiagnosticLinesProvider] adds. Empty
/// when there is no stderr and no added line, or no parseable entry in
/// them.
///
/// Watches [elaborationStderrProvider] so the drawer auto-refreshes
/// as elaboration completes; the stderr parser itself
/// ([yosysErrorDiagnosticProvider]) is keyed by the raw text so
/// re-parses only happen when the text changes.
@Riverpod(keepAlive: true)
List<YosysDiagnostic> elaborationDiagnostics(Ref ref) {
  final added = ref.watch(overlayDiagnosticLinesProvider);
  final stderr = ref.watch(elaborationStderrProvider);
  final text = added.isEmpty ? stderr : '${added.join('\n')}\n$stderr';
  if (text.isEmpty) return const <YosysDiagnostic>[];
  return ref.watch(yosysErrorDiagnosticProvider(text));
}

/// Active filter for the diagnostics drawer's severity chips. The
/// filter persists across rebuilds so the user's narrowing choice
/// survives every elaboration.
///
/// Default: every severity is on (set initialised to all values).
@Riverpod(keepAlive: true)
class ElaborationDiagnosticFilter extends _$ElaborationDiagnosticFilter {
  @override
  Set<YosysDiagnosticSeverity> build() =>
      Set<YosysDiagnosticSeverity>.from(YosysDiagnosticSeverity.values);

  /// Toggles [severity] in the filter set. If the severity is the
  /// only one active, the filter is reset to all severities (we
  /// never produce an empty filter — empty would mean "show
  /// nothing", which is a worse UX than no filter).
  void toggle(YosysDiagnosticSeverity severity) {
    final next = Set<YosysDiagnosticSeverity>.from(state);
    if (next.contains(severity)) {
      next.remove(severity);
      if (next.isEmpty) {
        state = Set<YosysDiagnosticSeverity>.from(
          YosysDiagnosticSeverity.values,
        );
        return;
      }
    } else {
      next.add(severity);
    }
    state = next;
  }

  /// Restores the filter to "show all severities".
  void reset() {
    final all = Set<YosysDiagnosticSeverity>.from(
      YosysDiagnosticSeverity.values,
    );
    if (state.length == all.length && state.containsAll(all)) return;
    state = all;
  }
}

/// Filtered diagnostics — the drawer reads this rather than the
/// raw list so the filter chips apply transparently.
@Riverpod(keepAlive: true)
List<YosysDiagnostic> filteredElaborationDiagnostics(Ref ref) {
  final all = ref.watch(elaborationDiagnosticsProvider);
  final filter = ref.watch(elaborationDiagnosticFilterProvider);
  if (filter.length == YosysDiagnosticSeverity.values.length) return all;
  return <YosysDiagnostic>[
    for (final entry in all)
      if (filter.contains(entry.severity)) entry,
  ];
}
