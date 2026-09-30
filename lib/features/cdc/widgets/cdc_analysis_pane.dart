// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_result.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing_kind.dart';
import 'package:netcrux/domain/models/cdc/cdc_severity.dart';
import 'package:netcrux/domain/models/cdc/cdc_synchronizer_status.dart';
import 'package:netcrux/features/cdc/providers/cdc_analysis_state_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Open-core CDC analysis pane — the crossings body shared by every
/// build tier.
///
/// Reads the current analysis result, severity filter, and selected
/// crossing from [cdcAnalysisStateProvider]. When no analysis has run
/// the empty-state explainer renders; when a result is present the
/// pane renders the crossings grouped by source→destination domain
/// pair, filtered by the state's active severity set. Each row
/// surfaces the severity icon, the signal name, and a localized
/// `kind · synchronizer status · confidence` subtitle.
///
/// The Pro overlay's `CdcAnalysisPanel` mounts this widget as its body
/// and adds the panel chrome around it (tier badge + summary header,
/// severity filter chips mutating the same state provider, re-run
/// action, footer). That panel is the only place this widget is mounted:
/// the open-core build refuses the CDC actions with a "requires NetCrux
/// Pro" notice and mounts no pane. The rendering lives here rather than in
/// the overlay so the crossings body is tested without it.
///
/// Selection-sync: tapping a crossing row invokes [onSelectCrossing]
/// when supplied. The Pro overlay routes this into the per-tab CDC
/// selection state; open-core ships [onSelectCrossing] = null which
/// renders the rows non-interactive.
class CdcAnalysisPane extends ConsumerWidget {
  /// Creates the CDC analysis pane.
  const CdcAnalysisPane({this.onSelectCrossing, super.key});

  /// Invoked when the user taps a crossing row. The hosting Pro panel
  /// typically routes the call into the per-tab CDC selection state so
  /// the corresponding crossing highlights. Null disables the callback
  /// (renders rows but doesn't fire).
  final void Function(CdcCrossing)? onSelectCrossing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(cdcAnalysisStateProvider);
    final result = state.result;
    if (result.isEmpty) {
      return CruxPanelEmptyState(
        icon: Icons.timeline_outlined,
        message:
            '${l10n.cdcAnalysisPaneEmptyTitle}\n'
            '${l10n.cdcAnalysisPaneEmptyHint}',
      );
    }
    return _CrossingsByDomainPairBody(
      l10n: l10n,
      result: result,
      severityFilter: state.severityFilter,
      selectedCrossingId: state.selectedCrossingId,
      onSelectCrossing: onSelectCrossing,
    );
  }
}

/// The crossings list grouped by (source domain, destination domain)
/// pair, honoring the state provider's severity filter. Detection
/// order is preserved within each group; group keys sort
/// lexicographically for a stable presentation.
class _CrossingsByDomainPairBody extends StatelessWidget {
  const _CrossingsByDomainPairBody({
    required this.l10n,
    required this.result,
    required this.severityFilter,
    required this.selectedCrossingId,
    required this.onSelectCrossing,
  });

  final L10N l10n;
  final CdcAnalysisResult result;
  final Set<CdcSeverity> severityFilter;
  final String? selectedCrossingId;
  final void Function(CdcCrossing)? onSelectCrossing;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<CdcCrossing>>{};
    final pairLabels = <String, String>{};
    for (final c in result.detectedCrossings) {
      if (!severityFilter.contains(c.severity)) continue;
      final key = '${c.sourceDomainId}__${c.destinationDomainId}';
      groups.putIfAbsent(key, () => <CdcCrossing>[]).add(c);
      if (!pairLabels.containsKey(key)) {
        final src = result.domainById(c.sourceDomainId);
        final dst = result.domainById(c.destinationDomainId);
        pairLabels[key] = l10n.cdcAnalysisPaneDomainPairHeader(
          src?.clockSignalName ?? c.sourceDomainId,
          dst?.clockSignalName ?? c.destinationDomainId,
        );
      }
    }
    final sortedKeys = groups.keys.toList()..sort();
    return ListView.builder(
      itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        final key = sortedKeys[index];
        return _DomainPairGroup(
          l10n: l10n,
          headerText: pairLabels[key]!,
          crossings: groups[key]!,
          selectedCrossingId: selectedCrossingId,
          onSelectCrossing: onSelectCrossing,
        );
      },
    );
  }
}

class _DomainPairGroup extends StatelessWidget {
  const _DomainPairGroup({
    required this.l10n,
    required this.headerText,
    required this.crossings,
    required this.selectedCrossingId,
    required this.onSelectCrossing,
  });

  final L10N l10n;
  final String headerText;
  final List<CdcCrossing> crossings;
  final String? selectedCrossingId;
  final void Function(CdcCrossing)? onSelectCrossing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          color: theme.colorScheme.surfaceContainer,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            headerText,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
        for (final c in crossings)
          _CrossingRow(
            l10n: l10n,
            crossing: c,
            isHighlighted: c.id == selectedCrossingId,
            onTap: onSelectCrossing == null ? null : () => onSelectCrossing!(c),
          ),
      ],
    );
  }
}

class _CrossingRow extends StatelessWidget {
  const _CrossingRow({
    required this.l10n,
    required this.crossing,
    required this.isHighlighted,
    required this.onTap,
  });

  final L10N l10n;
  final CdcCrossing crossing;
  final bool isHighlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: l10n.cdcAnalysisPaneCrossingTooltip(crossing.signalName),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: isHighlighted ? cs.primary.withValues(alpha: 0.10) : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: <Widget>[
              Icon(
                _iconForSeverity(crossing.severity),
                size: 14,
                color: _colorForSeverity(crossing.severity),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      crossing.signalName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      l10n.cdcAnalysisPaneCrossingSubtitle(
                        _labelForKind(l10n, crossing.crossingKind),
                        _labelForStatus(l10n, crossing.synchronizerStatus),
                        _labelForConfidence(l10n, crossing.confidence),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _labelForKind(L10N l10n, CdcCrossingKind kind) {
  switch (kind) {
    case CdcCrossingKind.singleBit:
      return l10n.cdcCrossingKindSingleBit;
    case CdcCrossingKind.multiBit:
      return l10n.cdcCrossingKindMultiBit;
    case CdcCrossingKind.control:
      return l10n.cdcCrossingKindControl;
    case CdcCrossingKind.handshake:
      return l10n.cdcCrossingKindHandshake;
  }
}

String _labelForStatus(L10N l10n, CdcSynchronizerStatus status) {
  switch (status) {
    case CdcSynchronizerStatus.properTwoFlopSync:
      return l10n.cdcSynchronizerStatusProperTwoFlop;
    case CdcSynchronizerStatus.properThreeFlopSync:
      return l10n.cdcSynchronizerStatusProperThreeFlop;
    case CdcSynchronizerStatus.asyncFifo:
      return l10n.cdcSynchronizerStatusAsyncFifo;
    case CdcSynchronizerStatus.handshakeProtocol:
      return l10n.cdcSynchronizerStatusHandshake;
    case CdcSynchronizerStatus.customSynchronizer:
      return l10n.cdcSynchronizerStatusCustom;
    case CdcSynchronizerStatus.missingSynchronizer:
      return l10n.cdcSynchronizerStatusMissing;
    case CdcSynchronizerStatus.metastable:
      return l10n.cdcSynchronizerStatusMetastable;
  }
}

String _labelForConfidence(L10N l10n, CdcConfidence confidence) {
  switch (confidence) {
    case CdcConfidence.high:
      return l10n.cdcConfidenceHigh;
    case CdcConfidence.medium:
      return l10n.cdcConfidenceMedium;
    case CdcConfidence.low:
      return l10n.cdcConfidenceLow;
  }
}

IconData _iconForSeverity(CdcSeverity s) {
  switch (s) {
    case CdcSeverity.critical:
      return Icons.error_outline;
    case CdcSeverity.warning:
      return Icons.warning_amber_outlined;
    case CdcSeverity.info:
      return Icons.info_outline;
  }
}

Color _colorForSeverity(CdcSeverity s) {
  switch (s) {
    case CdcSeverity.critical:
      return Colors.red.shade700;
    case CdcSeverity.warning:
      return Colors.amber.shade800;
    case CdcSeverity.info:
      return Colors.green.shade700;
  }
}
