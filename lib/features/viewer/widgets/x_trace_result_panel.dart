// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/x_trace_in_flight_provider.dart';
import 'package:netcrux/features/viewer/providers/x_trace_result_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/schematic/net_name_lookup.dart';
import 'package:netcrux/shared/yosys_names.dart';

/// The X-trace result panel: the causal chain the back-cone walker produced,
/// rendered as a depth-ordered list under a one-line termination status.
///
/// **Open-core on purpose.** The *walk* is Pro — `xTraceServiceProvider`
/// resolves to `NoopXTraceService` without the overlay — but the panel is not,
/// because `showXTracePanel` is an open-core action and the ARB's own empty
/// string promises a panel that opens with nothing in it. An open-core build
/// therefore shows this surface, permanently in its empty state; the Pro
/// overlay contributes the chain and the schematic context-menu entry that
/// starts one.
///
/// **No header and no in-panel Clear.** The `crux_dock` strip supplies the
/// icon, the title, the `×` and the actions cluster (the suite dock-strip
/// canon), so a header here would draw all four a second time twelve pixels
/// lower. This is the one place NetCrux deliberately does not copy WaveCrux's
/// identically-named panel, which predates the dock-strip canon and still
/// draws its own 32 px header.
///
/// **Three states, and no error state.** `XTraceService.trace` is
/// contractually "never throws" and expresses every failure as a termination
/// reason, so there is nothing an error slot could hold that the status row
/// cannot say better. If a case appears the six terminations cannot express,
/// add a seventh termination and its ARB key rather than a free-form string.
class XTraceResultPanel extends ConsumerWidget {
  /// Creates the X-trace result panel.
  const XTraceResultPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final result = ref.watch(xTraceResultProvider);
    final inFlight = ref.watch(xTraceInFlightProvider);

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Hidden while empty: `noTraceableSelection` is the sentinel for
          // "nothing has run", not a result worth reporting, and the empty
          // state already says what to do instead.
          if (!result.isEmpty) _StatusRow(result: result),
          // The progress line replaces the divider rather than pushing the
          // list down, so a walk starting does not reflow the rows the user
          // is reading.
          if (inFlight)
            const LinearProgressIndicator(minHeight: 2)
          else
            const Divider(height: 1),
          Expanded(
            child: result.isEmpty
                ? _EmptyState(message: l10n.xTracePanelEmpty)
                : _ChainList(result: result),
          ),
        ],
      ),
    );
  }
}

/// Centred explainer shown before the first walk, after Clear, and for the
/// whole life of an open-core build.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// One line: why the walk stopped, and how far it got.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.result});

  final XTraceResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final (icon, tone) = terminationStyle(result.termination, theme);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusLabel(l10n, result),
              style: theme.textTheme.bodySmall?.copyWith(color: tone),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.xTracePanelStepCount(result.chain.length),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The localized status label for [termination].
///
/// Exhaustive across all six `XTraceTermination` values even though the walker
/// emits only four: `noTraceableSelection` arrives with `XTraceResult.empty`,
/// and `noVcdLoaded` has no producer at all today — it is reserved for X-trace
/// v2, which is blocked on a time cursor and a working waveform file picker
/// rather than on the VCD parser (that ships). Keeping the case costs a line
/// and keeps the switch total.
String terminationLabel(L10N l10n, XTraceTermination termination) =>
    switch (termination) {
      XTraceTermination.foundOrigin => l10n.xTracePanelTerminationFoundOrigin,
      XTraceTermination.maxDepthReached => l10n.xTracePanelTerminationMaxDepth,
      XTraceTermination.reachedBoundary => l10n.xTracePanelTerminationBoundary,
      XTraceTermination.noVcdLoaded => l10n.xTracePanelTerminationNoVcd,
      XTraceTermination.cycleDetected => l10n.xTracePanelTerminationCycle,
      XTraceTermination.noTraceableSelection =>
        l10n.xTracePanelTerminationNothing,
    };

/// The status row's text for [result]: [terminationLabel], extended with
/// the origin reason when the walk found an origin and says why the cell is
/// one. A pin-level reason names the pin by its port name, the part of
/// `originPortId` after the cell name.
String statusLabel(L10N l10n, XTraceResult result) {
  final reason = result.termination == XTraceTermination.foundOrigin
      ? result.originReason
      : null;
  if (reason == null) return terminationLabel(l10n, result.termination);
  final pin = _pinName(result.originPortId);
  final text = switch (reason) {
    XTraceOriginReason.undrivenInput => l10n.xTracePanelOriginReasonUndriven(
      pin,
    ),
    XTraceOriginReason.xTiedInput => l10n.xTracePanelOriginReasonXTied(pin),
    XTraceOriginReason.registerWithoutReset =>
      l10n.xTracePanelOriginReasonNoReset,
    XTraceOriginReason.noDrivenInputs => l10n.xTracePanelOriginReasonNoInputs,
  };
  return l10n.xTracePanelTerminationFoundOriginWithReason(text);
}

/// `<cellName>:<portName>` → `<portName>`. Cut at the last colon, since a
/// Yosys cell name carries its source location (`$mul$mac.v:25$1:B`).
String _pinName(String? portId) {
  if (portId == null) return '';
  final colon = portId.lastIndexOf(':');
  return colon < 0 ? portId : portId.substring(colon + 1);
}

/// Icon and tone for [termination]. An answer (origin / boundary) reads as
/// primary, a bail-out (depth limit) as tertiary, and a cycle as an error —
/// a combinational loop is a design defect, not a walk outcome.
(IconData, Color) terminationStyle(
  XTraceTermination termination,
  ThemeData theme,
) => switch (termination) {
  XTraceTermination.foundOrigin => (Icons.gps_fixed, theme.colorScheme.primary),
  XTraceTermination.reachedBoundary => (Icons.login, theme.colorScheme.primary),
  XTraceTermination.maxDepthReached => (
    Icons.more_horiz,
    theme.colorScheme.tertiary,
  ),
  XTraceTermination.cycleDetected => (Icons.loop, theme.colorScheme.error),
  XTraceTermination.noVcdLoaded => (
    Icons.info_outline,
    theme.colorScheme.onSurfaceVariant,
  ),
  XTraceTermination.noTraceableSelection => (
    Icons.info_outline,
    theme.colorScheme.onSurfaceVariant,
  ),
};

/// The chain, one row per step, in walk order.
///
/// No indentation: NetCrux's chain is linear and every row prints its own
/// depth. WaveCrux indents because its tree has an actual parent/child level.
class _ChainList extends ConsumerWidget {
  const _ChainList({required this.result});

  final XTraceResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolved once per build rather than once per row: every step in a chain
    // is intra-scope by construction (the walker never leaves the scope it
    // started in), so they all resolve against the same module.
    final tree = ref.watch(hierarchyTreeProvider);
    final model = tree.model;
    final module = model == null ? null : tree.selected?.resolve(model);
    return ListView.builder(
      itemCount: result.chain.length,
      itemBuilder: (context, index) {
        final step = result.chain[index];
        return _StepRow(
          step: step,
          netName: netNameForId(module, step.netId),
          isTerminator: index == result.chain.length - 1,
          termination: result.termination,
          onTap: () => _onTapStep(context, ref, step),
        );
      },
    );
  }

  /// Selects the step's element and asks the viewport to reveal it.
  ///
  /// Called from a tap handler, never from `build` — the no-mutation-during-
  /// build invariant `AnalysisSelectionProbe` documents. The probe itself is
  /// the wrong tool here: it resolves *names* against the hierarchy, and these
  /// ids are already the current laid-out graph's, so the selection notifier
  /// is called directly. Selecting for real is what draws the canvas highlight
  /// and arms Cross-Probe's "Send selection", which reads
  /// `selectedElementProvider`.
  void _onTapStep(BuildContext context, WidgetRef ref, XTraceStep step) {
    final boundaryPortId = step.boundaryPortId;
    final cellId = step.cellId;
    final SelectedElement element;
    if (boundaryPortId != null) {
      element = SelectedElement.boundaryPort(
        portId: boundaryPortId,
        portName: stripPortPrefix(boundaryPortId),
      );
    } else if (step.edgeId.isNotEmpty) {
      element = SelectedElement.wire(edgeId: step.edgeId, netId: step.netId);
    } else if (cellId != null) {
      element = SelectedElement.cell(cellId: cellId);
    } else {
      return;
    }
    ref.read(selectedElementProvider.notifier).select(element);
    // Reveal is cell-addressed, so a wire step asks for its host cell — the
    // pair is adjacent on the canvas and framing the cell frames the wire.
    final revealTarget = cellId ?? _cellOfPort(boundaryPortId ?? step.edgeId);
    if (revealTarget != null) {
      ref.read(revealRequestProvider.notifier).request(revealTarget);
    }
  }

  /// `<cellName>:<portName>` → `<cellName>`, or `null` when [portId] names no
  /// cell (a `port:*` boundary id, or an edge id that is not a port id).
  static String? _cellOfPort(String portId) => cellIdOfPinId(portId);
}

/// Strips the `port:` prefix the graph builder applies to boundary-port ids,
/// leaving the bare port name a user recognises from their HDL.
String stripPortPrefix(String portId) =>
    portId.startsWith('port:') ? portId.substring('port:'.length) : portId;

/// One step: its depth, the net it is on, the cell or boundary port that hosts
/// the driver, and — when a waveform ever supplies one — the sampled value.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.netName,
    required this.isTerminator,
    required this.termination,
    required this.onTap,
  });

  final XTraceStep step;
  final String? netName;
  final bool isTerminator;
  final XTraceTermination termination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final boundaryPortId = step.boundaryPortId;
    final cellId = step.cellId;
    final value = step.value;

    // The last row is the answer to the question the user asked, so it carries
    // the status row's icon and bolds its primary line.
    final (terminatorIcon, terminatorTone) = terminationStyle(
      termination,
      theme,
    );

    final secondary = boundaryPortId != null
        ? l10n.xTracePanelStepBoundary(stripPortPrefix(boundaryPortId))
        : cellId != null
        ? l10n.xTracePanelStepCell(YosysNames.displayName(cellId))
        : null;
    // Generated names embed the whole source path; show the readable form
    // and keep the full name in a tooltip.
    final rawName = netName ?? '${step.netId}';
    final shownName = YosysNames.displayName(rawName);
    final fullNames = <String>[
      if (shownName != rawName) rawName,
      if (cellId != null && YosysNames.displayName(cellId) != cellId) cellId,
    ];

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 56,
              child: Text(
                l10n.xTracePanelStepLabel(step.depth),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: _MaybeTooltip(
                message: fullNames.join('\n'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      // Falls back to the raw Yosys id rather than showing
                      // nothing: an unresolvable net is rare (a bit with no
                      // named carrier in this scope) and an id the user can
                      // paste into a search beats a blank row.
                      shownName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: isTerminator
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (secondary != null)
                      Text(
                        secondary,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            // Null on every step until X-trace v2 samples a cursor time. The
            // branch is three lines and makes that a data change rather than
            // a UI change.
            if (value != null) ...<Widget>[
              const SizedBox(width: 8),
              Text(
                l10n.xTracePanelStepValue(value),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: step.isUnknown
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (isTerminator) ...<Widget>[
              const SizedBox(width: 8),
              Icon(terminatorIcon, size: 14, color: terminatorTone),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wraps [child] in a [Tooltip] showing [message], or returns [child] alone
/// when there is nothing the row shortened.
class _MaybeTooltip extends StatelessWidget {
  const _MaybeTooltip({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      message.isEmpty ? child : Tooltip(message: message, child: child);
}
