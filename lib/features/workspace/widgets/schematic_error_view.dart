// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/yosys/yosys_unavailable_reason_text.dart';

/// Elaboration-failure view shown on the schematic canvas when the
/// project failed to elaborate.
///
/// Wraps every error in a localized "Elaboration failed" envelope: known
/// typed [LoadedNetlistException] shapes render a localized, actionable
/// message; anything else gets a generic localized message. The raw
/// detail (Yosys stderr, an unclassified error's text) is tucked into an
/// expandable "Details" section so the envelope never leaks an exception
/// class name to the user.
class SchematicErrorView extends StatelessWidget {
  /// Creates an error view for [error].
  const SchematicErrorView({required this.error, super.key});

  /// The error surfaced by the elaboration/layout pipeline. A
  /// [LoadedNetlistException] is mapped to a per-[LoadedNetlistErrorKind]
  /// message; any other object falls back to the generic envelope.
  final Object error;

  /// Resolves the error into a localized body and an optional raw detail
  /// string for the expandable section.
  (String body, String? detail) _resolve(L10N l10n) {
    final e = error;
    if (e is LoadedNetlistException) {
      switch (e.kind) {
        case LoadedNetlistErrorKind.yosysUnavailable:
          // The reason code says which of four unrelated problems this
          // is; without it every one reads as "Yosys is not available"
          // and the raw code is left in the Details expander.
          final reason = yosysUnavailableReasonText(l10n, e.detail);
          return (reason ?? l10n.elaborationErrorYosysUnavailable, e.detail);
        case LoadedNetlistErrorKind.timeout:
          return (
            l10n.elaborationErrorTimeout(e.timeoutSeconds ?? 0),
            e.detail,
          );
        case LoadedNetlistErrorKind.nonZeroExit:
          return (l10n.elaborationErrorNonZeroExit(e.exitCode ?? 0), e.detail);
        case LoadedNetlistErrorKind.unknown:
          return (l10n.elaborationErrorGeneric, e.detail ?? e.message);
      }
    }
    return (l10n.elaborationErrorGeneric, e.toString());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10N.of(context);
    final (body, detail) = _resolve(l10n);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.elaborationErrorTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (detail != null && detail.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ErrorDetail(detail: detail),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Expandable, secondary-styled view of an error's raw detail text
/// (Yosys stderr, an unclassified error's `toString`). Collapsed by
/// default so the envelope stays clean; the monospace body is selectable
/// for copy/paste into a bug report.
class _ErrorDetail extends StatelessWidget {
  const _ErrorDetail({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // Strip the default divider lines so the expander reads as a quiet
      // secondary affordance rather than a heavy list row.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4),
        title: Text(
          L10N.of(context).elaborationErrorDetailsLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
