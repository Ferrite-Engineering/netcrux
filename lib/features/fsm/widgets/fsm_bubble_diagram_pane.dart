// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// a register…"); when an FSM is focused it lists the FSM's states and
/// transitions. The Pro overlay's FSM panel wraps this widget in panel
/// chrome and is the only place it is mounted: the open-core build refuses
/// the FSM actions with a "requires NetCrux Pro" notice and mounts no pane.
/// That panel shows this pane while no FSM is focused, and as the List view
/// of its Diagram | List header toggle: the accessible form of the bubble
/// canvas, which is a pointer surface.
///
/// The state list is one Tab stop. Up and Down (and Home and End) move a
/// roving focus between the state rows, each one named node; Enter or Space
/// on a row, or a click, fires [onSelectState] with that row's [FsmState].
/// The transition rows are text read in the list's reading order.
class FsmBubbleDiagramPane extends ConsumerWidget {
  /// Creates the bubble diagram pane.
  const FsmBubbleDiagramPane({this.onSelectState, super.key});

  /// Invoked when the user activates a state row (click, Enter or Space).
  /// Null leaves the rows focusable for reading but inert.
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

class _FallbackList extends StatefulWidget {
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
  State<_FallbackList> createState() => _FallbackListState();
}

class _FallbackListState extends State<_FallbackList> {
  final Map<String, FocusNode> _nodes = <String, FocusNode>{};

  /// The state row Tab lands on: the last focused row, else the highlighted
  /// state, else the first state.
  String? _stopId;
  String? _lastSelectedId;
  bool _pruneScheduled = false;

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(String id) =>
      _nodes[id] ??= FocusNode(debugLabel: 'FSM state row $id');

  bool get _listHasFocus => _nodes.values.any((node) => node.hasFocus);

  void _settleStop(List<String> ids) {
    final selected = widget.selectedStateId;
    if (selected != _lastSelectedId) {
      _lastSelectedId = selected;
      if (!_listHasFocus && ids.contains(selected)) _stopId = selected;
    }
    if (_stopId != null && ids.contains(_stopId)) return;
    _stopId = ids.contains(selected)
        ? selected
        : (ids.isEmpty ? null : ids.first);
  }

  /// Disposes the focus nodes of states a re-detection removed, after the
  /// frame that unmounted their rows.
  void _schedulePrune() {
    if (_pruneScheduled) return;
    _pruneScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pruneScheduled = false;
      if (!mounted) return;
      final live = widget.fsm.states.map((s) => s.id).toSet();
      final stale = _nodes.keys.where((id) => !live.contains(id)).toList();
      for (final id in stale) {
        _nodes.remove(id)?.dispose();
      }
    });
  }

  void _onRowFocused(String id) {
    // Deferred: this runs from a focus-node listener, and the rebuild it
    // triggers changes other rows' focus-node properties.
    scheduleMicrotask(() {
      if (!mounted || _stopId == id) return;
      setState(() => _stopId = id);
    });
  }

  /// Moves the roving focus to the state at [index] and scrolls it in, to
  /// the bottom edge when moving down the list and the top edge moving up.
  void _focusRow(int index, {required bool downward}) {
    final states = widget.fsm.states;
    if (index < 0 || index >= states.length) return;
    final id = states[index].id;
    if (_stopId != id) setState(() => _stopId = id);
    final node = _nodes[id];
    if (node == null) return;
    node.requestFocus();
    final rowContext = node.context;
    if (rowContext == null) return;
    Scrollable.ensureVisible(
      rowContext,
      alignmentPolicy: downward
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final states = widget.fsm.states;
    final current = states.indexWhere(
      (s) => _nodes[s.id]?.hasPrimaryFocus ?? false,
    );
    if (current == -1) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _focusRow(current + 1, downward: true);
      case LogicalKeyboardKey.arrowUp:
        _focusRow(current - 1, downward: false);
      case LogicalKeyboardKey.home:
        _focusRow(0, downward: false);
      case LogicalKeyboardKey.end:
        _focusRow(states.length - 1, downward: true);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// The one name a screen reader announces for a state row: its name, its
  /// encoded value and each badge the row shows.
  String _rowLabel(FsmState state) {
    final l10n = widget.l10n;
    return <String>[
      state.name,
      l10n.fsmBubbleDiagramStateValue(state.value),
      if (state.id == widget.fsm.resetStateId) l10n.fsmBubbleDiagramResetBadge,
      if (!state.isReachable) l10n.fsmBubbleDiagramUnreachableBadge,
      if (state.isTerminal) l10n.fsmBubbleDiagramTerminalBadge,
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final fsm = widget.fsm;
    final selectedStateId = widget.selectedStateId;
    final onSelectState = widget.onSelectState;
    _settleStop(fsm.states.map((s) => s.id).toList());
    _schedulePrune();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(l10n: l10n, fsm: fsm),
        const Divider(height: 1),
        Expanded(
          // Every row is built (an FSM has tens of states, not thousands), so
          // the roving focus can always reach and scroll to its target row.
          child: SingleChildScrollView(
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              includeSemantics: false,
              onKeyEvent: _onKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _SectionHeader(text: l10n.fsmBubbleDiagramStatesSection),
                  for (final s in fsm.states)
                    _StateRow(
                      key: ValueKey<String>(s.id),
                      l10n: l10n,
                      state: s,
                      semanticLabel: _rowLabel(s),
                      isReset: s.id == fsm.resetStateId,
                      isHighlighted: s.id == selectedStateId,
                      focusNode: _nodeFor(s.id),
                      isTabStop: s.id == _stopId,
                      onFocusChange: (focused) {
                        if (focused) _onRowFocused(s.id);
                      },
                      onActivate: onSelectState == null
                          ? null
                          : () => onSelectState(s),
                    ),
                  _SectionHeader(
                    text: l10n.fsmBubbleDiagramTransitionsSection,
                  ),
                  for (final t in fsm.transitions)
                    _TransitionRow(l10n: l10n, fsm: fsm, transition: t),
                  if (selectedStateId != null)
                    _HighlightFooter(
                      l10n: l10n,
                      highlightedName:
                          fsm.stateById(selectedStateId)?.name ??
                          selectedStateId,
                    ),
                ],
              ),
            ),
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

/// One state of the list: a single named, focusable node whose visible text
/// is excluded from semantics because [semanticLabel] already says it.
class _StateRow extends StatefulWidget {
  const _StateRow({
    required this.l10n,
    required this.state,
    required this.semanticLabel,
    required this.isReset,
    required this.isHighlighted,
    required this.focusNode,
    required this.isTabStop,
    required this.onFocusChange,
    required this.onActivate,
    super.key,
  });

  final L10N l10n;
  final FsmState state;
  final String semanticLabel;
  final bool isReset;
  final bool isHighlighted;
  final FocusNode focusNode;
  final bool isTabStop;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback? onActivate;

  @override
  State<_StateRow> createState() => _StateRowState();
}

class _StateRowState extends State<_StateRow> {
  bool _focused = false;

  void _tap() {
    widget.focusNode.requestFocus();
    widget.onActivate?.call();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      final activate = widget.onActivate;
      if (activate == null) return KeyEventResult.ignored;
      activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final state = widget.state;
    final isReset = widget.isReset;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      container: true,
      button: widget.onActivate != null,
      selected: widget.isHighlighted,
      label: widget.semanticLabel,
      onTap: widget.onActivate,
      child: Focus(
        focusNode: widget.focusNode,
        skipTraversal: !widget.isTabStop,
        onKeyEvent: _onKey,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          widget.onFocusChange(focused);
        },
        child: InkWell(
          onTap: _tap,
          canRequestFocus: false,
          excludeFromSemantics: true,
          child: ExcludeSemantics(
            child: Container(
              decoration: BoxDecoration(
                color: widget.isHighlighted
                    ? cs.primary.withValues(alpha: 0.10)
                    : null,
                border: _focused
                    ? Border.all(color: cs.tertiary, width: 2)
                    : null,
              ),
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
          ),
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
