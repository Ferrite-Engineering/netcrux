// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/fsm/fsm.dart';
import 'package:netcrux/domain/models/fsm/fsm_state.dart';
import 'package:netcrux/domain/models/fsm/fsm_transition.dart';
import 'package:netcrux/features/fsm/providers/selected_fsm_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Open-core FSM bubble diagram pane.
///
/// Reads the currently-focused FSM from [selectedFsmProvider]. When
/// no FSM is focused the empty-state explainer renders ("Right-click
/// a register…"); when an FSM is focused it surfaces a simple text list
/// of states + transitions. The Pro overlay's `FsmBubbleDiagramPanel`
/// wraps this widget in panel chrome + the actual force-directed canvas,
/// and is the only place it is mounted: the open-core build refuses the
/// FSM actions with a "requires NetCrux Pro" notice and mounts no pane.
/// That panel mounts this widget only while no FSM is focused and shows its
/// canvas otherwise, so a shipped build renders only the empty state; the
/// state list is reached by tests alone.
///
/// Selection-sync: when the user taps a state row in the list, the
/// [onSelectState] callback fires with the tapped [FsmState]. No mount
/// passes one — the Pro panel's canvas owns state selection — so the rows
/// render non-interactive.
class FsmBubbleDiagramPane extends ConsumerWidget {
  /// Creates the bubble diagram pane.
  const FsmBubbleDiagramPane({this.onSelectState, super.key});

  /// Invoked when the user taps a state row. Null disables the callback
  /// (renders rows but doesn't fire); no mount supplies one.
  final void Function(FsmState)? onSelectState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(selectedFsmProvider);
    final fsm = state.fsm;
    if (fsm == null) {
      return CruxPanelEmptyState(
        icon: Icons.account_tree_outlined,
        message:
            '${l10n.fsmBubbleDiagramEmptyTitle}\n'
            '${l10n.fsmBubbleDiagramEmptyHint}',
      );
    }
    return _FallbackList(
      l10n: l10n,
      fsm: fsm,
      selectedStateId: state.selectedStateId,
      onSelectState: onSelectState,
    );
  }
}

class _FallbackList extends StatelessWidget {
  const _FallbackList({
    required this.l10n,
    required this.fsm,
    required this.selectedStateId,
    required this.onSelectState,
  });

  final L10N l10n;
  final Fsm fsm;
  final String? selectedStateId;
  final void Function(FsmState)? onSelectState;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(l10n: l10n, fsm: fsm),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: <Widget>[
              _SectionHeader(text: l10n.fsmBubbleDiagramStatesSection),
              for (final s in fsm.states)
                _StateRow(
                  l10n: l10n,
                  state: s,
                  isReset: s.id == fsm.resetStateId,
                  isHighlighted: s.id == selectedStateId,
                  onTap: onSelectState == null ? null : () => onSelectState!(s),
                ),
              _SectionHeader(text: l10n.fsmBubbleDiagramTransitionsSection),
              for (final t in fsm.transitions)
                _TransitionRow(l10n: l10n, fsm: fsm, transition: t),
              if (selectedStateId != null)
                _HighlightFooter(
                  l10n: l10n,
                  highlightedName:
                      fsm.stateById(selectedStateId!)?.name ?? selectedStateId!,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.l10n, required this.fsm});

  final L10N l10n;
  final Fsm fsm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surfaceContainer,
      child: Text(
        l10n.fsmBubbleDiagramHeader(
          fsm.stateRegisterName,
          fsm.states.length,
          fsm.transitions.length,
        ),
        style: theme.textTheme.labelMedium,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({
    required this.l10n,
    required this.state,
    required this.isReset,
    required this.isHighlighted,
    required this.onTap,
  });

  final L10N l10n;
  final FsmState state;
  final bool isReset;
  final bool isHighlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isHighlighted ? cs.primary.withValues(alpha: 0.10) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(
              isReset ? Icons.flag_outlined : Icons.circle_outlined,
              size: 14,
              color: isReset
                  ? Colors.green.shade700
                  : (state.isReachable
                        ? cs.onSurfaceVariant
                        : cs.onSurfaceVariant.withValues(alpha: 0.5)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    state.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: state.isReachable
                          ? null
                          : cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    l10n.fsmBubbleDiagramStateValue(state.value),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isReset)
              _MetaBadge(
                text: l10n.fsmBubbleDiagramResetBadge,
                color: Colors.green.shade700,
              ),
            if (!state.isReachable) ...<Widget>[
              const SizedBox(width: 4),
              _MetaBadge(
                text: l10n.fsmBubbleDiagramUnreachableBadge,
                color: cs.onSurfaceVariant,
              ),
            ],
            if (state.isTerminal) ...<Widget>[
              const SizedBox(width: 4),
              _MetaBadge(
                text: l10n.fsmBubbleDiagramTerminalBadge,
                color: Colors.amber.shade800,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransitionRow extends StatelessWidget {
  const _TransitionRow({
    required this.l10n,
    required this.fsm,
    required this.transition,
  });

  final L10N l10n;
  final Fsm fsm;
  final FsmTransition transition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fromName =
        fsm.stateById(transition.fromStateId)?.name ?? transition.fromStateId;
    final toName =
        fsm.stateById(transition.toStateId)?.name ?? transition.toStateId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(
            transition.isSelfLoop ? Icons.refresh : Icons.arrow_right_alt,
            size: 14,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.fsmBubbleDiagramTransitionLine(
                fromName,
                toName,
                transition.conditionExpression ?? '',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightFooter extends StatelessWidget {
  const _HighlightFooter({
    required this.l10n,
    required this.highlightedName,
  });

  final L10N l10n;
  final String highlightedName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        l10n.fsmBubbleDiagramHighlighted(highlightedName),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
