// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';
import 'package:netcrux/features/diff/providers/diff_pane_state_provider.dart';
import 'package:netcrux/features/diff/widgets/diff_row_label.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Open-core Netlist Diff View widget.
///
/// Renders the active comparison held by [diffPaneStateProvider]:
///
///   * **Header row:** summary line (`N added, M removed, ...`) and
///     modification-intensity percentage.
///   * **Body:** scrollable change list grouped by [ElementChangeKind]
///     (Added / Removed / Modified) — `Unchanged` is omitted by
///     default since it bloats the list without adding signal; the
///     Pro panel surfaces it via a separate filter chip if the user
///     wants to see it.
///   * **Empty / computing / error states:** mirror the source-pane
///     pattern.
///
/// Each row carries:
///
///   * The element's leaf name (with the full canonical path shown
///     beneath in a smaller font),
///   * A small element-kind badge (`Instance` / `Net` / `Port` /
///     `Module`),
///   * For `Modified` rows, a list of differing attribute names,
///   * A trailing Show in Schematic button that calls [onShowInSchematic]
///     with the row's [ElementChange] so the hosting Pro panel can
///     route into the active-tab selection provider. It is a compact
///     icon button with a tooltip, so it stays visible at any panel
///     width; the text label joins the icon only when the row has room
///     ([showInSchematicLabelMinWidth]). The name truncates first.
///
/// Clicking a row does the same as its button: it selects the row and
/// shows that row's element.
///
/// The widget itself is layout-agnostic and tier-agnostic — the
/// Pro overlay's `DiffPanePanel` wraps it in panel chrome + tier badge
/// + filter chips + navigation footer. That panel is the only place it is
/// mounted: the open-core build refuses the diff actions with a "requires
/// NetCrux Pro" notice and mounts no pane.
class DiffPane extends ConsumerWidget {
  /// Creates the diff pane widget.
  const DiffPane({this.onShowInSchematic, super.key});

  /// Invoked when the user clicks a change row or its Show in Schematic
  /// button, with that row's change. The hosting panel routes the call
  /// into the active tab's selection provider so the schematic selects
  /// and reveals the element. Null leaves the rows without a button.
  final void Function(ElementChange)? onShowInSchematic;

  /// The row content width from which Show in Schematic carries its text
  /// label beside the icon. Narrower rows show the icon alone, with the
  /// label as its tooltip.
  static const double showInSchematicLabelMinWidth = 400;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(diffPaneStateProvider);

    if (state.errorMessage != null) {
      return _ErrorState(l10n: l10n, message: state.errorMessage!);
    }
    if (state.isComputing) {
      return _ComputingState(l10n: l10n);
    }
    if (!state.hasActiveDiff) {
      return CruxPanelEmptyState(
        icon: Icons.compare_arrows,
        message:
            '${l10n.diffPaneEmptyTitle}\n'
            '${l10n.diffPaneEmptyHint}',
      );
    }
    final filtered = state.filteredChanges;
    if (filtered.isEmpty) {
      return _NoFilterMatchesState(l10n: l10n, summary: state.activeDiff!);
    }
    return _LoadedView(
      l10n: l10n,
      diff: state.activeDiff!,
      changes: filtered,
      selectedIndex: state.selectedChangeIndex,
      onShowInSchematic: onShowInSchematic,
      onSelectRow: (index) =>
          ref.read(diffPaneStateProvider.notifier).selectChange(index),
    );
  }
}

// ── states ──────────────────────────────────────────────────────────

class _ComputingState extends StatelessWidget {
  const _ComputingState({required this.l10n});

  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 12),
          Text(l10n.diffPaneComputing, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.l10n, required this.message});

  final L10N l10n;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 28, color: theme.colorScheme.error),
            const SizedBox(height: 8),
            Text(
              l10n.diffPaneEmptyTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoFilterMatchesState extends StatelessWidget {
  const _NoFilterMatchesState({required this.l10n, required this.summary});

  final L10N l10n;
  final NetlistDiff summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SummaryHeader(l10n: l10n, diff: summary),
        const Divider(height: 1),
        Expanded(
          child: CruxPanelEmptyState(message: l10n.diffPaneNoFilterMatches),
        ),
      ],
    );
  }
}

// ── loaded view ─────────────────────────────────────────────────────

class _LoadedView extends StatelessWidget {
  const _LoadedView({
    required this.l10n,
    required this.diff,
    required this.changes,
    required this.selectedIndex,
    required this.onShowInSchematic,
    required this.onSelectRow,
  });

  final L10N l10n;
  final NetlistDiff diff;
  final List<ElementChange> changes;
  final int? selectedIndex;
  final void Function(ElementChange)? onShowInSchematic;
  final void Function(int index) onSelectRow;

  @override
  Widget build(BuildContext context) {
    final byKind = <ElementChangeKind, List<int>>{};
    for (var i = 0; i < changes.length; i++) {
      byKind.putIfAbsent(changes[i].kind, () => <int>[]).add(i);
    }
    // The same order [DiffPaneState.filteredChanges] uses, so a row's
    // position in the list is its navigation index.
    final groups = <_DiffGroup>[
      for (final k in DiffPaneState.displayOrder)
        if (byKind[k] != null && byKind[k]!.isNotEmpty)
          _DiffGroup(kind: k, indices: byKind[k]!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SummaryHeader(l10n: l10n, diff: diff),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _flatItemCount(groups),
            itemBuilder: (context, position) {
              final lookup = _resolvePosition(groups, position);
              if (lookup.isHeader) {
                return _GroupHeader(
                  l10n: l10n,
                  kind: lookup.group.kind,
                  count: lookup.group.indices.length,
                );
              }
              final changeIndex = lookup.group.indices[lookup.rowIndex];
              final change = changes[changeIndex];
              final isSelected = selectedIndex == changeIndex;
              final show = onShowInSchematic;
              final onSchematic = isOnSchematic(change);
              return _ChangeRow(
                l10n: l10n,
                change: change,
                isSelected: isSelected,
                // Clicking a row is the primary way to show its element, and
                // its button does the same: select the row, then show this
                // row's own element. The element is passed directly, never
                // looked up again by index, so the reveal is exactly the row
                // clicked and the active row is the one shown. Clicking the
                // selected row again shows it again.
                onTap: () {
                  onSelectRow(changeIndex);
                  if (onSchematic) show?.call(change);
                },
                hasShowInSchematic: show != null,
                onShowInSchematic: show == null || !onSchematic
                    ? null
                    : () {
                        onSelectRow(changeIndex);
                        show(change);
                      },
              );
            },
          ),
        ),
      ],
    );
  }

  int _flatItemCount(List<_DiffGroup> groups) {
    var n = 0;
    for (final g in groups) {
      n += g.indices.length + 1; // header + rows
    }
    return n;
  }

  _PositionLookup _resolvePosition(List<_DiffGroup> groups, int position) {
    var pos = position;
    for (final g in groups) {
      if (pos == 0) {
        return _PositionLookup(group: g, isHeader: true, rowIndex: -1);
      }
      pos -= 1;
      if (pos < g.indices.length) {
        return _PositionLookup(group: g, isHeader: false, rowIndex: pos);
      }
      pos -= g.indices.length;
    }
    // Defensive fallback — should never hit if _flatItemCount is correct.
    return _PositionLookup(group: groups.last, isHeader: false, rowIndex: 0);
  }
}

/// Whether [change]'s element is in the design the schematic shows.
///
/// The schematic shows the baseline: the tab's own elaboration. Removed,
/// modified and unchanged elements exist there; an added element exists
/// only in the comparison netlist, so there is nothing to show.
bool isOnSchematic(ElementChange change) =>
    change.kind != ElementChangeKind.added;

class _DiffGroup {
  _DiffGroup({required this.kind, required this.indices});

  final ElementChangeKind kind;
  final List<int> indices;
}

class _PositionLookup {
  _PositionLookup({
    required this.group,
    required this.isHeader,
    required this.rowIndex,
  });

  final _DiffGroup group;
  final bool isHeader;
  final int rowIndex;
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.l10n, required this.diff});

  final L10N l10n;
  final NetlistDiff diff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surfaceContainer,
      child: Text(
        l10n.diffPaneSummary(
          diff.summary.totalAdded,
          diff.summary.totalRemoved,
          diff.summary.totalModified,
          diff.summary.totalUnchanged,
        ),
        style: theme.textTheme.labelMedium,
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.l10n,
    required this.kind,
    required this.count,
  });

  final L10N l10n;
  final ElementChangeKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        _labelFor(l10n, kind, count),
        style: theme.textTheme.labelSmall?.copyWith(
          color: _colorFor(theme.colorScheme, kind),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _labelFor(L10N l10n, ElementChangeKind kind, int count) {
    switch (kind) {
      case ElementChangeKind.added:
        return l10n.diffPaneGroupAdded(count);
      case ElementChangeKind.removed:
        return l10n.diffPaneGroupRemoved(count);
      case ElementChangeKind.modified:
        return l10n.diffPaneGroupModified(count);
      case ElementChangeKind.unchanged:
        return l10n.diffPaneGroupUnchanged(count);
    }
  }

  Color _colorFor(ColorScheme cs, ElementChangeKind kind) {
    switch (kind) {
      case ElementChangeKind.added:
        return Colors.green.shade700;
      case ElementChangeKind.removed:
        return Colors.red.shade700;
      case ElementChangeKind.modified:
        return Colors.amber.shade800;
      case ElementChangeKind.unchanged:
        return cs.onSurfaceVariant;
    }
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.l10n,
    required this.change,
    required this.isSelected,
    required this.onTap,
    required this.hasShowInSchematic,
    required this.onShowInSchematic,
  });

  final L10N l10n;
  final ElementChange change;
  final bool isSelected;
  final VoidCallback onTap;

  /// Whether the host panel routes Show in Schematic at all. Without one
  /// the row carries no button.
  final bool hasShowInSchematic;

  /// Null when the element is not on the schematic: the button is then
  /// disabled and its tooltip says why.
  final VoidCallback? onShowInSchematic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = DiffRowLabel.of(change);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Tooltip(
                message: label.tooltip,
                child: Text(
                  label.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _ElementKindBadge(l10n: l10n, elementKind: change.elementKind),
          ],
        ),
        Text(
          label.subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            fontSize: 10,
            color: cs.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (change.modifiedAttributes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              change.modifiedAttributes.join(', '),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: Colors.amber.shade800,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? cs.primary.withValues(alpha: 0.10) : null,
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: <Widget>[
              _KindIcon(kind: change.kind),
              const SizedBox(width: 8),
              // The name gives way first: it truncates, and the button
              // keeps its place at the row's end.
              Expanded(child: details),
              if (hasShowInSchematic)
                _ShowInSchematicButton(
                  l10n: l10n,
                  onPressed: onShowInSchematic,
                  withLabel:
                      constraints.maxWidth >=
                      DiffPane.showInSchematicLabelMinWidth,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row's Show in Schematic button: the icon alone with the label as its
/// tooltip, or the icon and the label when the row is wide enough. Disabled
/// when [onPressed] is null, with a tooltip saying why: the element is not
/// in the design the schematic shows.
class _ShowInSchematicButton extends StatelessWidget {
  const _ShowInSchematicButton({
    required this.l10n,
    required this.onPressed,
    required this.withLabel,
  });

  final L10N l10n;
  final VoidCallback? onPressed;
  final bool withLabel;

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.center_focus_strong, size: 14);
    final button = withLabel
        ? TextButton.icon(
            onPressed: onPressed,
            icon: icon,
            label: Text(
              l10n.diffPaneShowInSchematic,
              style: const TextStyle(fontSize: 10),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(28, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          )
        : IconButton(
            onPressed: onPressed,
            icon: icon,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
    if (onPressed == null) {
      return Tooltip(
        message: l10n.diffPaneShowInSchematicComparisonOnly,
        child: button,
      );
    }
    return withLabel
        ? button
        : Tooltip(message: l10n.diffPaneShowInSchematic, child: button);
  }
}

class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind});

  final ElementChangeKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (kind) {
      case ElementChangeKind.added:
        return Icon(
          Icons.add_circle_outline,
          size: 14,
          color: Colors.green.shade700,
        );
      case ElementChangeKind.removed:
        return Icon(
          Icons.remove_circle_outline,
          size: 14,
          color: Colors.red.shade700,
        );
      case ElementChangeKind.modified:
        return Icon(
          Icons.edit_outlined,
          size: 14,
          color: Colors.amber.shade800,
        );
      case ElementChangeKind.unchanged:
        return Icon(
          Icons.check_circle_outline,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        );
    }
  }
}

class _ElementKindBadge extends StatelessWidget {
  const _ElementKindBadge({required this.l10n, required this.elementKind});

  final L10N l10n;
  final NetlistDiffElementKind elementKind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _labelFor(l10n, elementKind),
        style: TextStyle(
          fontSize: 9,
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _labelFor(L10N l10n, NetlistDiffElementKind kind) {
    switch (kind) {
      case NetlistDiffElementKind.instance:
        return l10n.diffPaneElementKindInstance;
      case NetlistDiffElementKind.net:
        return l10n.diffPaneElementKindNet;
      case NetlistDiffElementKind.port:
        return l10n.diffPaneElementKindPort;
      case NetlistDiffElementKind.module:
        return l10n.diffPaneElementKindModule;
    }
  }
}
