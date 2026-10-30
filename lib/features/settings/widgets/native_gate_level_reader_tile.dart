// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Settings → Engines → Native gate-level reader (beta).
///
/// On, a structural Verilog netlist is read straight into the netlist model
/// with no Yosys run; a design the reader cannot handle faithfully falls back
/// to Yosys and Diagnostics says why. Off, every design goes through Yosys.
/// A project's `netlistReader` key and the `--netlist-reader` flag override
/// this switch.
class NativeGateLevelReaderTile extends ConsumerWidget {
  /// Creates the tile showing whether the reader is [enabled].
  const NativeGateLevelReaderTile({required this.enabled, super.key});

  /// Widget key of the toggle, so tests can drive it locale-independently.
  static const Key switchKey = Key('settingsNativeGateLevelReaderSwitch');

  /// The saved switch at build time.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: CruxFormRow.toggle(
        key: switchKey,
        label: l10n.settingsNativeReaderLabel,
        help: l10n.settingsNativeReaderDescription,
        value: enabled,
        onChanged: (value) => unawaited(
          ref
              .read(appSettingsProvider.notifier)
              .setNativeGateLevelReader(enabled: value),
        ),
      ),
    );
  }
}
