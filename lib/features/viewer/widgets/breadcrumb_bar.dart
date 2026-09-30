// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Path bar shown above the schematic canvas — e.g. `top.cpu.alu`.
///
/// Each segment is a clickable `TextButton` that jumps the viewer to
/// that scope. The first segment (the top module) is always present;
/// subsequent segments are appended as the user pushes into child
/// instances. Renders nothing when no design is loaded.
class BreadcrumbBar extends ConsumerWidget {
  /// Creates a breadcrumb bar.
  const BreadcrumbBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(hierarchyTreeProvider);
    final model = state.model;
    final selected = state.selected;
    if (model == null || selected == null) {
      return const SizedBox.shrink();
    }
    final segments = _segmentsFor(selected, model);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Tooltip(
          message: l10n.breadcrumbTooltip,
          waitDuration: const Duration(milliseconds: 600),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < segments.length; i++) ...<Widget>[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  _BreadcrumbSegment(
                    label: segments[i].label,
                    targetPath: segments[i].targetPath,
                    isCurrent: i == segments.length - 1,
                    tooltip: i == 0 ? l10n.breadcrumbRootTooltip : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the segment list for [node].
  ///
  /// Segment 0 is the top module (with empty target path); segment N
  /// (for N>0) is the Nth path entry with the prefix up to N as the
  /// target path so a click brings the user back to that depth.
  static List<_Segment> _segmentsFor(HierarchyNode node, NetlistModel model) {
    final top = model.topModule;
    final topName = top?.name ?? node.moduleName;
    final segments = <_Segment>[
      _Segment(label: topName, targetPath: const <String>[]),
    ];
    for (var i = 0; i < node.path.length; i++) {
      segments.add(
        _Segment(
          label: node.path[i],
          targetPath: node.path.sublist(0, i + 1),
        ),
      );
    }
    return segments;
  }
}

class _Segment {
  const _Segment({required this.label, required this.targetPath});
  final String label;
  final List<String> targetPath;
}

class _BreadcrumbSegment extends ConsumerWidget {
  const _BreadcrumbSegment({
    required this.label,
    required this.targetPath,
    required this.isCurrent,
    this.tooltip,
  });

  final String label;
  final List<String> targetPath;
  final bool isCurrent;
  final String? tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: isCurrent
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurfaceVariant,
      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
    );
    final button = TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: isCurrent
          ? null
          : () => ref
                .read(hierarchyTreeProvider.notifier)
                .selectByPath(targetPath),
      child: Text(label, style: style),
    );
    final tip = tooltip;
    if (tip == null) return button;
    return Tooltip(message: tip, child: button);
  }
}
