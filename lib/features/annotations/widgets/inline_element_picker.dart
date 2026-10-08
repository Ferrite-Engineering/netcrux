import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Searchable picker for a single schematic element when the
/// add-annotation flow is invoked without an active
/// selection (e.g. from the command palette).
///
/// Lists every cell + every boundary port + every wire in the
/// active-scope `currentLaidOutGraphProvider`'s graph, filterable by
/// substring search. Returns a [AnnotationTarget] on
/// selection or null on cancel.
class InlineElementPicker extends ConsumerStatefulWidget {
  /// Creates the picker.
  const InlineElementPicker({super.key});

  @override
  ConsumerState<InlineElementPicker> createState() =>
      _InlineElementPickerState();
}

class _InlineElementPickerState extends ConsumerState<InlineElementPicker> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final async = ref.watch(currentLaidOutGraphProvider);
    final graph = async.value?.graph;
    final candidates = graph == null
        ? const <_Candidate>[]
        : _buildCandidates(graph);
    final filtered = _filter(candidates, _query);

    return AlertDialog(
      title: Text(l10n.inlineElementPickerTitle),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: <Widget>[
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.inlineElementPickerSearchHint,
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        l10n.inlineElementPickerNoResults,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final candidate = filtered[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(_iconFor(candidate.kind), size: 16),
                          title: Text(candidate.label),
                          subtitle: Text(
                            _kindLabel(l10n, candidate.kind),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          onTap: () => Navigator.of(context).pop(
                            AnnotationTarget(
                              kind: candidate.kind,
                              targetId: candidate.targetId,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.inlineElementPickerCancel),
        ),
      ],
    );
  }

  List<_Candidate> _buildCandidates(SchematicGraph graph) {
    final out = <_Candidate>[];
    for (final cell in graph.cells) {
      out.add(
        _Candidate(
          kind: AnnotationTargetKind.cell,
          targetId: cell.id,
          label: cell.id,
        ),
      );
    }
    for (final port in graph.boundaryPorts) {
      out.add(
        _Candidate(
          kind: AnnotationTargetKind.boundaryPort,
          targetId: 'port:${port.name}',
          label: port.name,
        ),
      );
    }
    for (final edge in graph.edges) {
      out.add(
        _Candidate(
          kind: AnnotationTargetKind.net,
          targetId: edge.id,
          label: '${edge.id} (net ${edge.netId})',
        ),
      );
    }
    return out;
  }

  List<_Candidate> _filter(List<_Candidate> candidates, String query) {
    if (query.isEmpty) return candidates;
    final lower = query.toLowerCase();
    return candidates
        .where((c) => c.label.toLowerCase().contains(lower))
        .toList();
  }

  IconData _iconFor(AnnotationTargetKind kind) {
    switch (kind) {
      case AnnotationTargetKind.cell:
        return Icons.crop_square;
      case AnnotationTargetKind.port:
      case AnnotationTargetKind.boundaryPort:
        return Icons.electrical_services;
      case AnnotationTargetKind.net:
        return Icons.timeline;
      case AnnotationTargetKind.scope:
        return Icons.folder_outlined;
    }
  }

  String _kindLabel(L10N l10n, AnnotationTargetKind kind) {
    switch (kind) {
      case AnnotationTargetKind.cell:
        return l10n.inlineElementPickerKindCell;
      case AnnotationTargetKind.port:
      case AnnotationTargetKind.boundaryPort:
        return l10n.inlineElementPickerKindPort;
      case AnnotationTargetKind.net:
        return l10n.inlineElementPickerKindNet;
      case AnnotationTargetKind.scope:
        return l10n.inlineElementPickerKindScope;
    }
  }
}

class _Candidate {
  const _Candidate({
    required this.kind,
    required this.targetId,
    required this.label,
  });

  final AnnotationTargetKind kind;
  final String targetId;
  final String label;
}

/// Shows the inline element picker as a modal dialog. Returns the
/// selected [AnnotationTarget] or null on cancel.
///
/// The picker lists candidates from the per-tab
/// `currentLaidOutGraphProvider`. The dialog mounts under the root
/// navigator, outside the active tab's provider scope, so [container] —
/// the active tab's `ProviderContainer` — is threaded through an
/// [`UncontrolledProviderScope`] so the picker reads the active tab's
/// graph rather than the empty root one. When [container] is null (no
/// active tab) the picker renders its empty state.
///
/// `barrierDismissible: false`: a searchable picker holding a typed query
/// (`_searchController`) is an editor, picker or anything else holding
/// in-progress user input, so closing must be a deliberate act rather than a stray scrim click —
/// same treatment as the Symbol Manager's search field.
///
/// Not independently `ModalGuard`-wrapped: this function is reachable
/// only through `openAddAnnotationDialog`
/// (`annotation_actions.dart`), which is guarded at
/// its own entry point, so a re-entrant call never reaches here.
Future<AnnotationTarget?> showInlineElementPicker(
  BuildContext context, {
  required ProviderContainer? container,
}) {
  return showDialog<AnnotationTarget>(
    context: context,
    barrierDismissible: false,
    builder: (_) => container == null
        ? const InlineElementPicker()
        : UncontrolledProviderScope(
            container: container,
            child: const InlineElementPicker(),
          ),
  );
}
