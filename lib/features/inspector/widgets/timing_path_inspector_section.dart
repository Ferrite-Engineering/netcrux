// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/inspector/providers/received_timing_path_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// The Inspector's read-only "Timing path from …" section: a path a peer
/// sent from an implementation run, with the mapping the sender stated, the
/// path's registers (and where each landed in this design) and its
/// statements.
///
/// Shown above the selection's sections while this tab holds a path, so it
/// is readable without a gesture and whatever is selected; Dismiss clears
/// it. The mapping is shown as the sender stated it, as a labelled chip:
/// colour is never its only channel, and it is never shown stronger than
/// sent.
class TimingPathInspectorSection extends ConsumerWidget {
  /// Creates the section.
  const TimingPathInspectorSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(receivedTimingPathProvider);
    if (path == null) return const SizedBox.shrink();
    final l10n = L10N.of(context);
    final mapping = timingPathFidelityLabel(l10n, path.fidelity);
    final rows = <Widget>[
      CruxInspectorValueRow(
        label: l10n.inspectorTimingPathMapping,
        value: mapping,
      ),
      for (var i = 0; i < path.registers.length; i++)
        CruxInspectorValueRow(
          label: _registerLabel(l10n, i, path.registers.length),
          value: _registerValue(l10n, path.registers[i]),
        ),
      for (var i = 0; i < path.statements.length; i++)
        CruxInspectorValueRow(
          label: i == 0 ? l10n.inspectorTimingPathStatements : '',
          value: path.statements[i],
        ),
      if (!path.resolved)
        Text(
          l10n.inspectorTimingPathNothingHere,
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ];
    return Semantics(
      container: true,
      liveRegion: true,
      label: l10n.inspectorTimingPathAnnouncement(path.peer, mapping),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: CruxInspectorSection(
          key: const ValueKey<String>('timingPathInspectorSection'),
          title: l10n.inspectorTimingPathTitle(path.peer),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _FidelityChip(label: mapping, fidelity: path.fidelity),
              const SizedBox(width: 4),
              TextButton(
                key: const ValueKey<String>('timingPathDismiss'),
                onPressed: () =>
                    ref.read(receivedTimingPathProvider.notifier).dismiss(),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                ),
                child: Text(l10n.inspectorTimingPathDismiss),
              ),
            ],
          ),
          children: rows,
        ),
      ),
    );
  }

  static String _registerLabel(L10N l10n, int index, int count) {
    if (index == 0) return l10n.inspectorTimingPathStart;
    if (index == count - 1) return l10n.inspectorTimingPathEnd;
    return '';
  }

  static String _registerValue(L10N l10n, TimingPathRegister register) =>
      switch (register.place) {
        TimingPathRegisterPlace.shown => register.name,
        TimingPathRegisterPlace.otherScope =>
          l10n.inspectorTimingPathOtherScope(register.name),
        TimingPathRegisterPlace.notFound => l10n.inspectorTimingPathNotFound(
          register.name,
        ),
      };
}

/// The words for a mapping, as Flow's tier map names them.
String timingPathFidelityLabel(L10N l10n, TimingPathFidelity fidelity) =>
    switch (fidelity) {
      TimingPathFidelity.register => l10n.timingPathFidelityRegister,
      TimingPathFidelity.statement => l10n.timingPathFidelityStatement,
      TimingPathFidelity.span => l10n.timingPathFidelitySpan,
      TimingPathFidelity.unmapped => l10n.timingPathFidelityUnmapped,
    };

/// The mapping as a small outlined chip. Its words carry the meaning; the
/// outline weight only echoes it (solid for an exact register).
class _FidelityChip extends StatelessWidget {
  const _FidelityChip({required this.label, required this.fidelity});

  final String label;
  final TimingPathFidelity fidelity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: scheme.onSurfaceVariant,
            width: fidelity == TimingPathFidelity.register ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
