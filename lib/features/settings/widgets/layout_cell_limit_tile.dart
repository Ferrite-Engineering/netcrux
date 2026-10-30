// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Settings → Engines → Largest scope laid out automatically.
///
/// A scope with more cells than the chosen number waits for "Lay out anyway"
/// instead of laying out when it is opened (see `scopeLayoutGateProvider`).
/// The choices are a few round numbers around the default plus "No limit";
/// a number saved by hand that is not among them is offered as one more
/// choice, so the control always shows what is in force.
class LayoutCellLimitTile extends ConsumerWidget {
  /// Creates the tile showing [currentLimit], the saved number of cells (`0`
  /// for no limit).
  const LayoutCellLimitTile({required this.currentLimit, super.key});

  /// The numbers of cells offered besides "No limit".
  static const List<int> choices = <int>[20000, 40000, 80000, 160000];

  /// The saved limit at build time.
  final int currentLimit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final numbers = <int>{
      ...choices,
      if (currentLimit > 0) currentLimit,
    }.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: CruxFormRow(
        label: l10n.settingsLayoutCellLimitLabel,
        help: l10n.settingsLayoutCellLimitDescription,
        mergeSemantics: false,
        child: CruxSegmentedControl<int>(
          segments: <CruxSegment<int>>[
            for (final count in numbers)
              CruxSegment<int>(
                value: count,
                label: l10n.settingsLayoutCellLimitChoice(count),
              ),
            CruxSegment<int>(
              value: 0,
              label: l10n.settingsLayoutCellLimitNone,
            ),
          ],
          selected: currentLimit < 0 ? 0 : currentLimit,
          semanticLabel: l10n.settingsLayoutCellLimitLabel,
          onChanged: (limit) => unawaited(
            ref.read(appSettingsProvider.notifier).setLayoutCellLimit(limit),
          ),
        ),
      ),
    );
  }
}
