// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Shown in place of the schematic after the user cancelled the elaboration
/// (or the read of a netlist): says so, and starts the same sources again on
/// request.
class SchematicElaborationStoppedView extends ConsumerWidget {
  /// Creates the stopped view.
  const SchematicElaborationStoppedView({super.key});

  /// Widget key of the retry button, so tests can drive it
  /// locale-independently.
  static const Key retryKey = Key('schematicElaborationRetry');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            l10n.schematicElaborationStopped,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: retryKey,
            onPressed: () => ref.invalidate(loadedNetlistProvider),
            child: Text(l10n.schematicElaborationRetry),
          ),
        ],
      ),
    );
  }
}
