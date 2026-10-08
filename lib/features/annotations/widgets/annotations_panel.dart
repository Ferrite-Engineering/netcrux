import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/features/annotations/providers/annotation_reveal_request.dart';
import 'package:netcrux/features/annotations/services/annotation_target_reveal.dart';
import 'package:netcrux/features/annotations/widgets/annotation_dialog.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';
import 'package:netcrux/shared/widgets/revealing_list_view.dart';

/// Panel listing the annotations of the active tab's design, docked as the
/// right dock's Annotations tab.
///
/// Watches [annotationSnapshotProvider], which the per-tab override list
/// re-binds, so the list rebuilds on every add / update / remove and shows
/// only the annotations made in this tab.
///
/// Each row leads with the annotation's title, or the first line of its
/// body when it has none, then names its element and author. The rest of
/// the body renders below through `flutter_markdown_plus`'s [MarkdownBody];
/// the edit dialog shows the raw Markdown source. A row is one focusable,
/// named control: activating it (click, Enter or Space) selects the
/// annotation's element on the schematic and brings it into view,
/// switching scope when the element is in another one.
///
/// A pending [annotationRevealRequestProvider] request (a badge click on
/// the schematic, or *Show Annotation*) scrolls the list to that
/// annotation and flashes its row, through the open-core
/// [RevealingListView].
class AnnotationsPanel extends ConsumerWidget {
  /// Creates the panel.
  const AnnotationsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final snapshot = ref.watch(annotationSnapshotProvider);
    final annotations = snapshot.annotations;
    final rows = annotationPanelRows(annotations);
    final revealId = ref.watch(annotationRevealRequestProvider);
    final revealIndex = revealId == null
        ? -1
        : rows.indexWhere((r) => r.annotation?.id == revealId);
    if (revealId != null && revealIndex < 0) {
      // A request for an annotation that is gone (deleted since) has no
      // row to answer it; drop it after this frame so it cannot fire
      // later against a row that reuses the id.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref
            .read(annotationRevealRequestProvider.notifier)
            .acknowledge(revealId);
      });
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  l10n.annotationsPanelTitle,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: annotations.isEmpty
                ? Center(
                    child: Text(
                      l10n.annotationsPanelEmpty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : RevealingListView(
                    itemCount: rows.length,
                    revealIndex: revealIndex < 0 ? null : revealIndex,
                    onRevealed: revealId == null
                        ? null
                        : () => ref
                              .read(annotationRevealRequestProvider.notifier)
                              .acknowledge(revealId),
                    itemBuilder: (context, i, {required flashing}) {
                      final row = rows[i];
                      final note = row.annotation;
                      if (note == null) {
                        return _LayerHeader(
                          layerId: row.layerId!,
                          label: row.layerLabel ?? '',
                          notes: row.layerNotes,
                        );
                      }
                      return _AnnotationTile(
                        annotation: note,
                        flashing: flashing,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One row of the Annotations panel: a note, or the header of a session
/// layer.
@immutable
class AnnotationPanelRow {
  /// A note row.
  const AnnotationPanelRow.note(Annotation this.annotation)
    : layerId = null,
      layerLabel = null,
      layerNotes = 0;

  /// A layer header row, over [layerNotes] notes.
  const AnnotationPanelRow.layer({
    required String this.layerId,
    required this.layerLabel,
    required this.layerNotes,
  }) : annotation = null;

  /// The note, or `null` for a layer header.
  final Annotation? annotation;

  /// The layer a header heads, or `null` for a note.
  final String? layerId;

  /// The layer's label.
  final String? layerLabel;

  /// How many notes the layer holds.
  final int layerNotes;
}

/// The panel's rows: notes written outside any session first, then each
/// session layer under its own header, in the order the layers first appear.
///
/// A layer is one meeting's notes. Grouped, a week-old review reads as one
/// named, collapsible thing with a date on it rather than as a dozen loose
/// notes nobody remembers writing.
List<AnnotationPanelRow> annotationPanelRows(List<Annotation> notes) {
  final rows = <AnnotationPanelRow>[
    for (final n in notes)
      if (n.sessionLayerId == null) AnnotationPanelRow.note(n),
  ];
  final layers = <String, List<Annotation>>{};
  for (final n in notes) {
    final layer = n.sessionLayerId;
    if (layer != null) layers.putIfAbsent(layer, () => []).add(n);
  }
  for (final MapEntry(key: layer, value: inLayer) in layers.entries) {
    rows
      ..add(
        AnnotationPanelRow.layer(
          layerId: layer,
          layerLabel: inLayer.first.sessionLayerLabel,
          layerNotes: inLayer.length,
        ),
      )
      ..addAll(inLayer.map(AnnotationPanelRow.note));
  }
  return rows;
}

/// The header of a session layer: its label, and the two things a layer does
/// as a unit — hide from the canvas, and delete.
class _LayerHeader extends ConsumerWidget {
  const _LayerHeader({
    required this.layerId,
    required this.label,
    required this.notes,
  });

  final String layerId;
  final String label;
  final int notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final inLayer = [
      for (final n in ref.watch(annotationSnapshotProvider).annotations)
        if (n.sessionLayerId == layerId) n,
    ];
    final hidden = inLayer.isNotEmpty && inLayer.every((n) => n.hidden);
    return Padding(
      key: ValueKey<String>('annotationLayer-$layerId'),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.layers_outlined, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ),
          IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: hidden
                ? l10n.annotationLayerShow
                : l10n.annotationLayerHide,
            icon: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () {
              final store = ref.read(annotationStoreProvider);
              for (final n in inLayer) {
                store.updateAnnotation(n.copyWith(hidden: !hidden));
              }
            },
          ),
          IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: l10n.annotationLayerDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirmed = await confirmCruxDestructiveAction(
                context,
                title: l10n.annotationLayerDeleteTitle,
                body: l10n.annotationLayerDeleteBody(notes),
                confirmLabel: l10n.annotationLayerDelete,
                cancelLabel: l10n.annotationDialogCancelButton,
              );
              if (!confirmed) return;
              final store = ref.read(annotationStoreProvider);
              for (final n in inLayer) {
                store.removeAnnotation(n.id);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _AnnotationTile extends ConsumerWidget {
  const _AnnotationTile({required this.annotation, required this.flashing});
  final Annotation annotation;

  /// True while the row answers a reveal request: a brief tint.
  final bool flashing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final author = annotation.author;
    // Somebody else's note: hidden or deleted, never edited while their name
    // is on it. In a session "somebody else" is anyone but the local
    // participant; once a session's notes are kept, the local participant's
    // own lose their author id and are editable again.
    final me = ref.watch(schematicCollabSessionProvider).value?.myParticipantId;
    final readOnly = annotation.authorId != null && annotation.authorId != me;
    final color = annotation.colorArgb;
    final heading = annotationRowHeading(annotation);
    final details = annotationRowDetails(annotation);
    final kind = annotationTargetKindLabel(l10n, annotation.targetKind);
    final label = <String>[
      l10n.annotationsPanelRowSemantics(heading, kind, annotation.targetId),
      if (author != null) l10n.annotationsPanelRowAuthor(author),
      if (details.isNotEmpty) annotationSpokenText(details),
    ].join('. ');
    final row = Semantics(
      container: true,
      button: true,
      label: label,
      onTap: () => _reveal(context, l10n),
      child: InkWell(
        key: ValueKey<String>('annotationRowTap-${annotation.id}'),
        excludeFromSemantics: true,
        onTap: () => _reveal(context, l10n),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // A session note wears its author's colour, frozen when it
                // was written.
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Icon(
                    Icons.sticky_note_2_outlined,
                    size: 18,
                    color: color == null ? null : Color(color),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        heading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$kind · ${annotation.targetId}'
                        '${author != null ? ' · $author' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (details.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        MarkdownBody(
                          data: details,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return AnimatedContainer(
      key: ValueKey<String>('annotationRow-${annotation.id}'),
      duration: const Duration(milliseconds: 250),
      color: theme.colorScheme.primary.withValues(alpha: flashing ? 0.30 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: row),
          PopupMenuButton<_AnnotationMenuAction>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (action) async {
              final store = ref.read(annotationStoreProvider);
              switch (action) {
                case _AnnotationMenuAction.edit:
                  final edited = await showAnnotationDialog(
                    context: context,
                    ref: ref,
                    targetKind: annotation.targetKind,
                    targetId: annotation.targetId,
                    existing: annotation,
                  );
                  if (edited != null) store.updateAnnotation(edited);
                case _AnnotationMenuAction.delete:
                  store.removeAnnotation(annotation.id);
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<_AnnotationMenuAction>>[
              if (!readOnly)
                PopupMenuItem<_AnnotationMenuAction>(
                  value: _AnnotationMenuAction.edit,
                  child: Text(l10n.annotationContextMenuEdit),
                ),
              PopupMenuItem<_AnnotationMenuAction>(
                value: _AnnotationMenuAction.delete,
                child: Text(l10n.annotationContextMenuDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Selects and reveals the annotation's element on this tab's schematic.
  /// The panel is mounted inside the tab's scope, so the container found
  /// here is the tab's.
  void _reveal(BuildContext context, L10N l10n) {
    final tab = ProviderScope.containerOf(context, listen: false);
    final found = revealAnnotationTarget(
      tab,
      kind: annotation.targetKind,
      targetId: annotation.targetId,
      moduleName: annotation.moduleName,
    );
    if (!found) {
      showCruxInfoSnack(
        context,
        l10n.annotationsPanelTargetNotFound(annotationRowHeading(annotation)),
      );
    }
  }
}

/// The line a panel row leads with: the annotation's title, the first line
/// of its body when untitled, or its element id when it has neither.
String annotationRowHeading(Annotation annotation) {
  final heading = annotation.heading;
  return heading.isEmpty ? annotation.targetId : heading;
}

/// The Markdown a panel row shows under its heading: the whole body for a
/// titled annotation, and the body after its first line for an untitled
/// one, whose first line is already the heading.
String annotationRowDetails(Annotation annotation) {
  final body = annotation.body.trim();
  if (annotation.title != null) return body;
  final firstBreak = body.indexOf('\n');
  return firstBreak < 0 ? '' : body.substring(firstBreak + 1).trim();
}

/// [markdown] as a screen reader should read it: emphasis and code marks,
/// heading and quote markers and list bullets dropped, lines joined.
String annotationSpokenText(String markdown) => markdown
    .split('\n')
    .map(
      (line) => line
          .replaceFirst(RegExp(r'^\s*(#{1,6}\s+|>\s?|[-*+]\s+)'), '')
          .replaceAll(RegExp('[*`~]'), '')
          .trim(),
    )
    .where((line) => line.isNotEmpty)
    .join(' ');

/// The localized name of an annotation target kind, as the panel and the
/// screen-reader labels show it.
String annotationTargetKindLabel(L10N l10n, AnnotationTargetKind kind) {
  switch (kind) {
    case AnnotationTargetKind.cell:
      return l10n.annotationTargetKindCell;
    case AnnotationTargetKind.port:
      return l10n.annotationTargetKindPort;
    case AnnotationTargetKind.boundaryPort:
      return l10n.annotationTargetKindBoundaryPort;
    case AnnotationTargetKind.net:
      return l10n.annotationTargetKindNet;
    case AnnotationTargetKind.scope:
      return l10n.annotationTargetKindScope;
  }
}

enum _AnnotationMenuAction { edit, delete }
