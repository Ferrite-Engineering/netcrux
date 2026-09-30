// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing_kind.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain_analysis_result.dart';
import 'package:netcrux/domain/models/reset_domain/reset_polarity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_synchronizer_status.dart';
import 'package:netcrux/domain/models/reset_domain/unreset_register.dart';
import 'package:netcrux/features/reset_domain/providers/reset_domain_analysis_state_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Open-core Reset Domain analysis pane — the crossings body shared by
/// every build tier.
///
/// Reads the current analysis result, severity filter, and selected
/// crossing from [resetDomainAnalysisStateProvider]. When no analysis
/// has run the empty-state explainer renders; when a result is present
/// the pane renders the crossings grouped by source→destination reset
/// domain pair, filtered by the state's active severity set. Each row
/// surfaces the severity icon, the signal name, and a localized
/// `kind · synchronizer status · polarity · confidence` subtitle.
///
/// The Pro overlay's `ResetDomainAnalysisPanel` mounts this widget as
/// its body and adds the panel chrome around it (tier badge + summary
/// header, severity filter chips mutating the same state provider,
/// re-run action, footer). That panel is the only place this widget is
/// mounted: the open-core build refuses the reset-domain actions with a
/// "requires NetCrux Pro" notice and mounts no pane. The rendering lives
/// here rather than in the overlay so the crossings body is tested
/// without it.
///
/// Selection-sync: tapping a crossing row invokes [onSelectCrossing]
/// when supplied. The Pro overlay routes this into the per-tab reset
/// selection state; open-core ships [onSelectCrossing] = null which
/// renders the rows non-interactive.
class ResetDomainAnalysisPane extends ConsumerWidget {
  /// Creates the Reset Domain analysis pane.
  const ResetDomainAnalysisPane({this.onSelectCrossing, super.key});

  /// Invoked when the user taps a crossing row. The hosting Pro panel
  /// typically routes the call into the per-tab reset selection state
  /// so the corresponding crossing highlights. Null disables the
  /// callback (renders rows but doesn't fire).
  final void Function(ResetCrossing)? onSelectCrossing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(resetDomainAnalysisStateProvider);
    final result = state.result;
    if (result.isEmpty) {
      return CruxPanelEmptyState(
        icon: Icons.restart_alt,
        message:
            '${l10n.resetDomainAnalysisPaneEmptyTitle}\n'
            '${l10n.resetDomainAnalysisPaneEmptyHint}',
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
  final ResetDomainAnalysisResult result;
  final Set<ResetSeverity> severityFilter;
  final String? selectedCrossingId;
  final void Function(ResetCrossing)? onSelectCrossing;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ResetCrossing>>{};
    final pairLabels = <String, String>{};
    for (final c in result.detectedCrossings) {
      if (!severityFilter.contains(c.severity)) continue;
      final key = '${c.sourceDomainId}__${c.destinationDomainId}';
      groups.putIfAbsent(key, () => <ResetCrossing>[]).add(c);
      if (!pairLabels.containsKey(key)) {
        final src = result.domainById(c.sourceDomainId);
        final dst = result.domainById(c.destinationDomainId);
        pairLabels[key] = l10n.resetDomainAnalysisPaneDomainPairHeader(
          src?.resetSignalName ?? c.sourceDomainId,
          dst?.resetSignalName ?? c.destinationDomainId,
        );
      }
    }
    final sortedKeys = groups.keys.toList()..sort();

    // Unreset-register findings are warning-severity, so they show
    // when the Warning filter chip is active. Rendered as a leading
    // section, above the crossing groups, so a missing-reset flop is
    // surfaced alongside the crossings rather than lost.
    final showUnreset =
        result.unresetRegisters.isNotEmpty &&
        severityFilter.contains(ResetSeverity.warning);

    return ListView(
      children: <Widget>[
        if (showUnreset)
          _UnresetSection(l10n: l10n, registers: result.unresetRegisters),
        for (final key in sortedKeys)
          _DomainPairGroup(
            l10n: l10n,
            headerText: pairLabels[key]!,
            crossings: groups[key]!,
            selectedCrossingId: selectedCrossingId,
            onSelectCrossing: onSelectCrossing,
          ),
      ],
    );
  }
}

/// The unreset-register findings section — registers with no reset,
/// which power up in an unknown (`X`) state. Warning-severity, display-only.
class _UnresetSection extends StatelessWidget {
  const _UnresetSection({required this.l10n, required this.registers});

  final L10N l10n;
  final List<UnresetRegister> registers;

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
            l10n.resetDomainAnalysisPaneUnresetSectionHeader,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
        for (final reg in registers) _UnresetRow(l10n: l10n, register: reg),
      ],
    );
  }
}

class _UnresetRow extends StatelessWidget {
  const _UnresetRow({required this.l10n, required this.register});

  final L10N l10n;
  final UnresetRegister register;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: l10n.resetDomainAnalysisPaneUnresetTooltip(
        register.registerName,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(
              _iconForSeverity(ResetSeverity.warning),
              size: 14,
              color: _colorForSeverity(ResetSeverity.warning),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    register.registerName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    l10n.resetDomainAnalysisPaneUnresetSubtitle,
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
  final List<ResetCrossing> crossings;
  final String? selectedCrossingId;
  final void Function(ResetCrossing)? onSelectCrossing;

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
  final ResetCrossing crossing;
  final bool isHighlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: l10n.resetDomainAnalysisPaneCrossingTooltip(
        crossing.signalName,
      ),
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
                      l10n.resetDomainAnalysisPaneCrossingSubtitle(
                        _labelForKind(l10n, crossing.crossingKind),
                        _labelForStatus(l10n, crossing.synchronizerStatus),
                        _labelForPolarity(l10n, crossing.sourcePolarity),
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

String _labelForKind(L10N l10n, ResetCrossingKind kind) {
  switch (kind) {
    case ResetCrossingKind.dataCrossesResetBoundary:
      return l10n.resetCrossingKindData;
    case ResetCrossingKind.resetDeassertCrossing:
      return l10n.resetCrossingKindDeassert;
  }
}

String _labelForStatus(L10N l10n, ResetSynchronizerStatus status) {
  switch (status) {
    case ResetSynchronizerStatus.properAsyncAssertSyncDeassert:
      return l10n.resetSynchronizerStatusProperAsyncSync;
    case ResetSynchronizerStatus.properSyncAssertSyncDeassert:
      return l10n.resetSynchronizerStatusProperSyncSync;
    case ResetSynchronizerStatus.properResetSynchronizer:
      return l10n.resetSynchronizerStatusProperResetSynchronizer;
    case ResetSynchronizerStatus.customSynchronizer:
      return l10n.resetSynchronizerStatusCustom;
    case ResetSynchronizerStatus.missingSynchronizer:
      return l10n.resetSynchronizerStatusMissing;
    case ResetSynchronizerStatus.glitchProne:
      return l10n.resetSynchronizerStatusGlitchProne;
  }
}

String _labelForPolarity(L10N l10n, ResetPolarity polarity) {
  switch (polarity) {
    case ResetPolarity.activeHigh:
      return l10n.resetPolarityActiveHigh;
    case ResetPolarity.activeLow:
      return l10n.resetPolarityActiveLow;
    case ResetPolarity.unknown:
      return l10n.resetPolarityUnknown;
  }
}

String _labelForConfidence(L10N l10n, ResetConfidence confidence) {
  switch (confidence) {
    case ResetConfidence.high:
      return l10n.resetConfidenceHigh;
    case ResetConfidence.medium:
      return l10n.resetConfidenceMedium;
    case ResetConfidence.low:
      return l10n.resetConfidenceLow;
  }
}

IconData _iconForSeverity(ResetSeverity s) {
  switch (s) {
    case ResetSeverity.critical:
      return Icons.error_outline;
    case ResetSeverity.warning:
      return Icons.warning_amber_outlined;
    case ResetSeverity.info:
      return Icons.info_outline;
  }
}

Color _colorForSeverity(ResetSeverity s) {
  switch (s) {
    case ResetSeverity.critical:
      return Colors.red.shade700;
    case ResetSeverity.warning:
      return Colors.amber.shade800;
    case ResetSeverity.info:
      return Colors.green.shade700;
  }
}
