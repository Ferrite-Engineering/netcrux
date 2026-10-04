// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing_kind.dart';
import 'package:netcrux/domain/models/reset_domain/reset_polarity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_synchronizer_status.dart';
import 'package:netcrux/domain/models/reset_domain/unreset_register.dart';
import 'package:netcrux/features/reset_domain/providers/reset_domain_analysis_state_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/revealing_list_view.dart';

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
///
/// The state's signal filter, when set, narrows the list to one signal's
/// crossings. A pending reveal request scrolls that crossing's row into
/// view and flashes it, then is acknowledged so the same request can be
/// raised again.
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
    final items = _groupedItems(l10n, state);
    final revealId = state.revealCrossingId;
    final revealIndex = revealId == null
        ? null
        : items.indexWhere((item) => item.crossing?.id == revealId);
    return RevealingListView(
      itemCount: items.length,
      revealIndex: revealIndex == null || revealIndex < 0 ? null : revealIndex,
      onRevealed: revealId == null
          ? null
          : () => ref
                .read(resetDomainAnalysisStateProvider.notifier)
                .acknowledgeReveal(revealId),
      itemBuilder: (context, index, {required flashing}) {
        final item = items[index];
        final crossing = item.crossing;
        final unreset = item.unreset;
        if (crossing != null) {
          return _CrossingRow(
            l10n: l10n,
            crossing: crossing,
            isHighlighted: crossing.id == state.selectedCrossingId,
            isFlashing: flashing,
            onTap: onSelectCrossing == null
                ? null
                : () => onSelectCrossing!(crossing),
          );
        }
        if (unreset != null) return _UnresetRow(l10n: l10n, register: unreset);
        return _GroupHeader(text: item.header!);
      },
    );
  }
}

/// One row of the flattened list: a section header, an unreset-register
/// finding, or a crossing.
class _Item {
  const _Item.header(String this.header) : unreset = null, crossing = null;
  const _Item.unreset(UnresetRegister this.unreset)
    : header = null,
      crossing = null;
  const _Item.crossing(ResetCrossing this.crossing)
    : header = null,
      unreset = null;

  final String? header;
  final UnresetRegister? unreset;
  final ResetCrossing? crossing;
}

/// The visible crossings grouped by (source domain, destination domain)
/// pair and flattened into header and crossing rows, after an optional
/// unreset-register section. Detection order is preserved within each
/// group; group keys sort lexicographically for a stable presentation.
List<_Item> _groupedItems(L10N l10n, ResetDomainAnalysisState state) {
  final result = state.result;
  final groups = <String, List<ResetCrossing>>{};
  final pairLabels = <String, String>{};
  for (final c in state.visibleCrossings) {
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

  // Unreset-register findings are warning-severity, so they show when the
  // Warning filter chip is active. Rendered as a leading section, above
  // the crossing groups, so a missing-reset flop is surfaced alongside the
  // crossings rather than lost. A signal filter is about one signal's
  // crossings, so it hides the section.
  final showUnreset =
      result.unresetRegisters.isNotEmpty &&
      state.severityFilter.contains(ResetSeverity.warning) &&
      state.signalFilter == null;

  return <_Item>[
    if (showUnreset) ...<_Item>[
      _Item.header(l10n.resetDomainAnalysisPaneUnresetSectionHeader),
      for (final reg in result.unresetRegisters) _Item.unreset(reg),
    ],
    for (final key in sortedKeys) ...<_Item>[
      _Item.header(pairLabels[key]!),
      for (final c in groups[key]!) _Item.crossing(c),
    ],
  ];
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
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

class _CrossingRow extends StatelessWidget {
  const _CrossingRow({
    required this.l10n,
    required this.crossing,
    required this.isHighlighted,
    required this.isFlashing,
    required this.onTap,
  });

  final L10N l10n;
  final ResetCrossing crossing;
  final bool isHighlighted;

  /// True while the row answers a reveal request: a stronger tint that
  /// fades back to the selected tint.
  final bool isFlashing;
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          color: isFlashing
              ? cs.primary.withValues(alpha: 0.30)
              : isHighlighted
              ? cs.primary.withValues(alpha: 0.10)
              : cs.primary.withValues(alpha: 0),
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
