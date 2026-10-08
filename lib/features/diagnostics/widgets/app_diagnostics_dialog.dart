// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_stats_strip/crux_stats_strip.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:netcrux/features/diagnostics/providers/netlist_footprint_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';

/// Tag this dialog holds on [cruxMemoryPollRequestProvider] while it is open.
const String kAppDiagnosticsMemoryTag = 'netcrux.app_diagnostics';

/// Process-wide App Diagnostics dialog.
///
/// The app-level surface of NetCrux's three-surface diagnostics model: the
/// Tab Diagnostics drawer answers "what happened on the last elaboration?",
/// the Pane Render Stats popover answers "why is this canvas slow?", and
/// this answers "what is the state of the app?" — the question someone is
/// actually being asked when they file a bug.
///
/// Four sections:
///
/// * **Memory** — process RSS, sampled live.
/// * **Per-tab design size** — modules / cells / nets for every open tab,
///   read out of each tab's own container. Counts rather than bytes; see
///   [NetlistFootprint] for why a byte figure would be invented.
/// * **Frame stats** — rolling FPS, frames over budget, last frame.
/// * **Session** — the privacy-scrubbed [cruxIssueSessionContextProvider],
///   the same contributor the beta issue reporter sends. One source means
///   the dialog and the filed issue can never disagree, and the privacy
///   contract is asserted once, in the contributor's own test.
class AppDiagnosticsDialog extends ConsumerStatefulWidget {
  /// Creates an [AppDiagnosticsDialog].
  const AppDiagnosticsDialog({super.key});

  /// Mounts the dialog as a modal rooted at [context]. Returns when dismissed.
  ///
  /// Re-entrancy guarded ([ModalGuard]): shortcut auto-repeat, a double-tap
  /// on the menu item, or the palette entry must not stack a second dialog.
  static Future<void> show(BuildContext context) => ModalGuard.run(
    'appDiagnostics',
    () => showDialog<void>(
      context: context,
      builder: (_) => const AppDiagnosticsDialog(),
    ),
  );

  /// Renders [session] as the Session section's plain-text body.
  static String reportFor(CruxIssueSessionContext session) {
    final buf = StringBuffer();
    if (session.isEmpty) {
      buf.writeln('(no session state available)');
      return buf.toString();
    }
    // Pad to the widest label so the monospace body reads as a table.
    final width = session.fields
        .map((f) => f.label.length)
        .reduce((a, b) => a > b ? a : b);
    for (final field in session.fields) {
      buf.writeln('${field.label.padRight(width)}  ${field.value}');
    }
    return buf.toString();
  }

  @override
  ConsumerState<AppDiagnosticsDialog> createState() =>
      _AppDiagnosticsDialogState();
}

class _AppDiagnosticsDialogState extends ConsumerState<AppDiagnosticsDialog> {
  final ScrollController _scrollController = ScrollController();

  /// Captured in [initState] because `ref` is unusable from [dispose] —
  /// it resolves through `BuildContext`, which is already deactivated by
  /// then. The notifier itself is not auto-disposed, so the reference stays
  /// valid for the container's lifetime.
  late final CruxMemoryPollRequestNotifier _pollRequests;

  @override
  void initState() {
    super.initState();
    _pollRequests = ref.read(cruxMemoryPollRequestProvider.notifier);
    // The RSS poller idles unless something is watching. Without this the
    // Memory section would read a permanent dash whenever the user had the
    // statistics strip collapsed — which is its default state.
    //
    // Deferred to the first post-frame slot: requesting synchronously here
    // mutates a provider other listeners watch, mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pollRequests.request(kAppDiagnosticsMemoryTag);
    });
  }

  @override
  void dispose() {
    _pollRequests.release(kAppDiagnosticsMemoryTag);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);

    // Closing post-frame rather than returning an empty dialog: the gate can
    // flip while the dialog is open (the user turns diagnostics off in
    // Settings), and a modal that stayed up showing nothing would be worse
    // than one that dismisses itself.
    if (!ref.watch(diagnosticsEnabledProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    final memory = ref.watch(cruxMemoryStatsProvider);
    final frame = ref.watch(cruxFrameStatsProvider);
    final session = ref.watch(cruxIssueSessionContextProvider);
    final tabs = _tabFootprints();

    return Dialog(
      child: SizedBox(
        width: 720,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.diagnosticsAppDialogTitle,
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          l10n.diagnosticsAppDialogSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('appDiagnosticsCopyReportButton'),
                    onPressed: () => _copyReport(
                      context,
                      l10n,
                      memory: memory,
                      frame: frame,
                      session: session,
                      tabs: tabs,
                    ),
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(l10n.diagnosticsCopyFullReport),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('appDiagnosticsCloseButton'),
                    icon: const Icon(Icons.close),
                    tooltip: l10n.diagnosticsCloseTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionHeader(
                        key: const Key('appDiagnosticsSectionMemory'),
                        title: l10n.diagnosticsSectionMemory,
                      ),
                      const SizedBox(height: 8),
                      _MetricsCard(
                        rows: [
                          _MetricRow(
                            label: l10n.diagnosticsMetricRss,
                            value: memory.hasSample
                                ? _formatBytes(memory.residentBytes)
                                : '—',
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SectionHeader(
                        key: const Key('appDiagnosticsSectionPerTab'),
                        title: l10n.diagnosticsSectionPerTab,
                      ),
                      const SizedBox(height: 8),
                      _PerTabTable(rows: tabs, l10n: l10n),
                      const SizedBox(height: 6),
                      Text(
                        l10n.diagnosticsPerTabNote,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionHeader(
                        key: const Key('appDiagnosticsSectionFrameStats'),
                        title: l10n.diagnosticsSectionFrameStats,
                      ),
                      const SizedBox(height: 8),
                      _MetricsCard(
                        rows: [
                          _MetricRow(
                            label: l10n.diagnosticsMetricFps,
                            value: frame.sampledFrames == 0
                                ? '—'
                                : frame.framesPerSecond.toStringAsFixed(1),
                          ),
                          _MetricRow(
                            label: l10n.diagnosticsMetricJank,
                            value: '${frame.budgetOverruns}',
                          ),
                          _MetricRow(
                            label: l10n.diagnosticsMetricLastFrame,
                            value: frame.sampledFrames == 0
                                ? '—'
                                : formatMicros(frame.lastFrameMicros),
                          ),
                          _MetricRow(
                            label: l10n.diagnosticsMetricSampledFrames,
                            value: '${frame.sampledFrames}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SectionHeader(
                        key: const Key('appDiagnosticsSectionSession'),
                        title: l10n.diagnosticsSectionSession,
                      ),
                      const SizedBox(height: 8),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            AppDiagnosticsDialog.reportFor(session),
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reads each open tab's footprint out of that tab's own container.
  ///
  /// Deliberately imperative rather than a second `UncontrolledProviderScope`
  /// over the per-tab containers — see the note atop `active_tab_container.dart`
  /// for why mounting one from outside `PaneHost` produced
  /// markNeedsBuild-during-build errors on launch.
  ///
  /// Returns an empty list when the workspace plumbing is absent (a bare
  /// unit-test container has no tab manager), so the dialog still opens.
  List<_TabFootprintRow> _tabFootprints() {
    final workspace = ref.watch(netcruxWorkspaceProvider).value;
    final manager = ref.watch(tabContainerManagerHolderProvider).manager;
    if (workspace == null || manager == null) return const <_TabFootprintRow>[];
    return <_TabFootprintRow>[
      for (final tab in workspace.tabs)
        _TabFootprintRow(
          id: tab.id,
          title: tab.displayName,
          footprint: manager
              .containerFor(tab.id)
              .read(netlistFootprintProvider),
        ),
    ];
  }

  Future<void> _copyReport(
    BuildContext context,
    L10N l10n, {
    required CruxMemoryStats memory,
    required CruxFrameStats frame,
    required CruxIssueSessionContext session,
    required List<_TabFootprintRow> tabs,
  }) async {
    final buf = StringBuffer()
      ..writeln('# NetCrux App Diagnostics')
      ..writeln()
      ..writeln('## Memory')
      ..writeln(
        'Process RSS  '
        '${memory.hasSample ? _formatBytes(memory.residentBytes) : '—'}',
      )
      ..writeln()
      ..writeln('## Per-tab design size (counts, not bytes)');
    if (tabs.isEmpty) {
      buf.writeln('(no tabs open)');
    } else {
      for (final row in tabs) {
        buf.writeln(
          '${row.title}: ${row.footprint.modules} modules, '
          '${row.footprint.cells} cells, ${row.footprint.nets} nets',
        );
      }
    }
    buf
      ..writeln()
      ..writeln('## Frame stats')
      ..writeln('FPS               ${frame.framesPerSecond.toStringAsFixed(1)}')
      ..writeln('Over budget       ${frame.budgetOverruns}')
      ..writeln('Last frame        ${formatMicros(frame.lastFrameMicros)}')
      ..writeln('Frames sampled    ${frame.sampledFrames}')
      ..writeln()
      ..writeln('## Session')
      ..write(AppDiagnosticsDialog.reportFor(session));

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!context.mounted) return;
    showCruxInfoSnack(context, l10n.diagnosticsCopiedToClipboard);
  }
}

/// One row of the per-tab design-size table.
class _TabFootprintRow {
  const _TabFootprintRow({
    required this.id,
    required this.title,
    required this.footprint,
  });

  final TabId id;
  final String title;
  final NetlistFootprint footprint;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.labelMedium?.copyWith(
        letterSpacing: 0.8,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.rows});

  final List<_MetricRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: <Widget>[
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(row.label, style: theme.textTheme.bodySmall),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        row.value,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _PerTabTable extends StatelessWidget {
  const _PerTabTable({required this.rows, required this.l10n});

  final List<_TabFootprintRow> rows;
  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          l10n.diagnosticsNoTabs,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // Horizontally scrollable so a long tab title never overflows the
        // dialog's fixed width into a yellow-and-black render error.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            key: const Key('appDiagnosticsPerTabTable'),
            columnSpacing: 24,
            headingRowHeight: 36,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 44,
            columns: [
              DataColumn(label: Text(l10n.diagnosticsColumnTab)),
              DataColumn(
                label: Text(l10n.diagnosticsColumnModules),
                numeric: true,
              ),
              DataColumn(
                label: Text(l10n.diagnosticsColumnCells),
                numeric: true,
              ),
              DataColumn(
                label: Text(l10n.diagnosticsColumnNets),
                numeric: true,
              ),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  // Namespaced so the row key never collides with a tab
                  // chip's own ValueKey(tab.id).
                  key: ValueKey<String>('diagTabRow:${row.id.value}'),
                  cells: [
                    DataCell(
                      Text(
                        row.title,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    DataCell(Text('${row.footprint.modules}')),
                    DataCell(Text('${row.footprint.cells}')),
                    DataCell(Text('${row.footprint.nets}')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a microsecond duration at human precision — sub-millisecond in
/// µs, everything else in ms.
String formatMicros(int micros) {
  if (micros < 1000) return '$micros µs';
  return '${(micros / 1000).toStringAsFixed(1)} ms';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
