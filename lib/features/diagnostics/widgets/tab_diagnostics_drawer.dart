// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Tab Diagnostics drawer for the project viewer.
///
/// Renders the **Elaboration Diagnostics** section: severity filter
/// chips (errors / warnings / info), the list of parsed
/// [YosysDiagnostic] entries for the current run, and a
/// "Copy Tab Diagnostics Report" action that puts the whole list on
/// the clipboard as structured plain text suitable for pasting into
/// a GitHub issue.
///
/// Rows are clickable: rows with a `file:line` copy the location to the
/// clipboard, which is exactly the "find in editor" workflow most
/// engineers use. Rows without a file:line fall back to a "find in
/// hierarchy" hand-off that selects the row's module in the
/// hierarchy tree when the module name is parseable from the
/// message.
class TabDiagnosticsDrawer extends ConsumerWidget {
  /// Creates a Tab Diagnostics drawer.
  const TabDiagnosticsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final diagnostics = ref.watch(filteredElaborationDiagnosticsProvider);
    final allDiagnostics = ref.watch(elaborationDiagnosticsProvider);
    final filter = ref.watch(elaborationDiagnosticFilterProvider);
    // Surface pipeline-level failures (yosys missing, source file
    // missing, parse error) that happen before Yosys could emit
    // stderr. Without this banner the drawer says "No diagnostics for
    // the current run." even though elaboration just failed.
    final loadedAsync = ref.watch(loadedNetlistProvider);
    final fatalError = loadedAsync.hasError ? loadedAsync.error : null;

    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // No title row: the drawer is the bottom dock's "Diagnostics"
            // tab and the strip already says so. The copy-report affordance
            // moved to the dock strip's action cluster
            // (`NetcruxBottomDock`), which calls [copyReportToClipboard].
            // Flexible + scrollable, NOT a bare child: the banner's height is
            // driven by the error message, and the bottom dock can be short
            // (its default leaves ~48 dp under the severity chips). An
            // unbounded banner overflowed the drawer — content the user
            // cannot see, on the one surface whose whole job is to explain
            // why elaboration failed. The common case, a missing yosys,
            // reaches exactly this path.
            //
            // Only reached when there IS a fatal error, so the no-error
            // layout is byte-identical to before: the widget is absent from
            // the tree and the list keeps the full height. When the banner is
            // present the list is empty by construction — elaboration failed
            // before Yosys emitted a diagnostic — so yielding half the space
            // to the message costs nothing.
            if (fatalError != null)
              Flexible(
                child: SingleChildScrollView(
                  child: _FatalErrorBanner(error: fatalError, l10n: l10n),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                _SeverityChip(
                  severity: YosysDiagnosticSeverity.error,
                  label: l10n.diagnosticSeverityError,
                  active: filter.contains(YosysDiagnosticSeverity.error),
                ),
                _SeverityChip(
                  severity: YosysDiagnosticSeverity.warning,
                  label: l10n.diagnosticSeverityWarning,
                  active: filter.contains(YosysDiagnosticSeverity.warning),
                ),
                _SeverityChip(
                  severity: YosysDiagnosticSeverity.info,
                  label: l10n.diagnosticSeverityInfo,
                  active: filter.contains(YosysDiagnosticSeverity.info),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: diagnostics.isEmpty
                  ? Center(
                      child: Text(
                        allDiagnostics.isEmpty
                            ? l10n.elaborationDiagnosticsEmpty
                            : l10n.elaborationDiagnosticsAllFiltered,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: diagnostics.length,
                      itemBuilder: (context, index) {
                        return _DiagnosticRow(
                          diagnostic: diagnostics[index],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Copies the full diagnostics report to the clipboard — the dock strip's
  /// copy action (the affordance that used to live in the drawer's own
  /// title row).
  static Future<void> copyReportToClipboard(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = L10N.of(context);
    final list = ref.read(elaborationDiagnosticsProvider);
    final report = StringBuffer()..writeln('Elaboration Diagnostics');
    for (final entry in list) {
      report.writeln('  ${_format(entry)}');
    }
    await Clipboard.setData(ClipboardData(text: report.toString()));
    if (!context.mounted) return;
    showCruxInfoSnack(context, l10n.elaborationDiagnosticsCopied);
  }

  static String _format(YosysDiagnostic d) {
    final loc = (d.filePath != null)
        ? '${d.filePath}${d.line != null ? ':${d.line}' : ''}: '
        : '';
    return '[${d.severity.name}] $loc${d.message}';
  }
}

class _FatalErrorBanner extends StatelessWidget {
  const _FatalErrorBanner({required this.error, required this.l10n});

  final Object error;
  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = error is LoadedNetlistException
        ? (error as LoadedNetlistException).message
        : '$error';
    final cause = error is LoadedNetlistException
        ? (error as LoadedNetlistException).cause
        : null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.elaborationDiagnosticsFatal,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          if (cause != null) ...<Widget>[
            const SizedBox(height: 4),
            SelectableText(
              '$cause',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeverityChip extends ConsumerWidget {
  const _SeverityChip({
    required this.severity,
    required this.label,
    required this.active,
  });

  final YosysDiagnosticSeverity severity;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilterChip(
      label: Text(label),
      selected: active,
      onSelected: (_) {
        ref.read(elaborationDiagnosticFilterProvider.notifier).toggle(severity);
      },
    );
  }
}

class _DiagnosticRow extends ConsumerWidget {
  const _DiagnosticRow({required this.diagnostic});

  final YosysDiagnostic diagnostic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = L10N.of(context);
    final hasLocation = diagnostic.filePath != null;
    final subtitle = hasLocation
        ? '${diagnostic.filePath}'
              '${diagnostic.line != null ? ':${diagnostic.line}' : ''}'
        : null;
    return ListTile(
      dense: true,
      leading: _severityIcon(theme, diagnostic.severity),
      title: Text(diagnostic.message),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: IconButton(
        tooltip: l10n.elaborationDiagnosticsCopyEntry,
        icon: const Icon(Icons.copy, size: 16),
        onPressed: () {
          unawaited(
            Clipboard.setData(
              ClipboardData(
                text: TabDiagnosticsDrawer._format(diagnostic),
              ),
            ),
          );
        },
      ),
      onTap: () => _onTap(context, ref),
    );
  }

  Widget _severityIcon(ThemeData theme, YosysDiagnosticSeverity severity) {
    switch (severity) {
      case YosysDiagnosticSeverity.error:
        return Icon(Icons.error_outline, color: theme.colorScheme.error);
      case YosysDiagnosticSeverity.warning:
        return Icon(
          Icons.warning_amber_outlined,
          color: theme.colorScheme.tertiary,
        );
      case YosysDiagnosticSeverity.info:
        return Icon(Icons.info_outline, color: theme.colorScheme.primary);
    }
  }

  void _onTap(BuildContext context, WidgetRef ref) {
    if (diagnostic.filePath != null) {
      // Copy the location to the clipboard so the user can paste it
      // into the editor's go-to-file dialog.
      final loc =
          '${diagnostic.filePath}'
          '${diagnostic.line != null ? ':${diagnostic.line}' : ''}';
      unawaited(Clipboard.setData(ClipboardData(text: loc)));
      return;
    }
    // No file:line — try to extract a module name from the message
    // (Yosys formats look like `Warning: in module foo: ...`).
    final match = RegExp(r'module\s+(?:\\)?([A-Za-z_][A-Za-z0-9_]*)')
        .firstMatch(
          diagnostic.message,
        );
    if (match == null) return;
    final moduleName = match.group(1)!;
    final tree = ref.read(hierarchyTreeProvider);
    final model = tree.model;
    if (model == null) return;
    // Walk the model to find any instance whose moduleName matches.
    for (final entry in model.modules.entries) {
      if (entry.key == moduleName) {
        ref.read(hierarchyTreeProvider.notifier).selectByPath(const []);
        return;
      }
    }
  }
}
