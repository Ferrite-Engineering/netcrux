// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/statistics/providers/elaboration_progress_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Shown in place of the schematic while the design is being elaborated by
/// Yosys, or a pre-built netlist is being read: what is running, the Yosys
/// pass when it has announced one, the time so far, and **Cancel**.
///
/// Elaboration of a design of millions of gates takes minutes, and with the
/// time limit set to No limit it takes as long as it takes, so the user can
/// always stop it from here. Cancel kills Yosys (or the worker that parses
/// its document) and leaves the canvas on [SchematicElaborationStoppedView].
class SchematicElaborationProgressView extends ConsumerStatefulWidget {
  /// Creates the progress view.
  const SchematicElaborationProgressView({super.key});

  /// Widget key of the Cancel button, so tests can drive it
  /// locale-independently.
  static const Key cancelKey = Key('schematicElaborationCancel');

  @override
  ConsumerState<SchematicElaborationProgressView> createState() =>
      _SchematicElaborationProgressViewState();
}

class _SchematicElaborationProgressViewState
    extends ConsumerState<SchematicElaborationProgressView> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Repaint the elapsed readout a few times a second; the view is replaced
    // the moment the elaboration ends, so the timer is short-lived.
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final reading = ref.watch(
      currentProjectProvider.select((project) => project.isPrebuiltNetlist),
    );
    final pass = ref.watch(elaborationProgressProvider);
    final seconds = (_stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    final elapsed = l10n.schematicLayoutElapsed(seconds);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              reading
                  ? l10n.schematicNetlistReadInProgress
                  : l10n.schematicElaborationInProgress,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              pass == null ? elapsed : '$pass · $elapsed',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: SchematicElaborationProgressView.cancelKey,
              onPressed: ref
                  .read(loadedNetlistProvider.notifier)
                  .cancelElaboration,
              child: Text(l10n.commonCancel),
            ),
          ],
        ),
      ),
    );
  }
}
