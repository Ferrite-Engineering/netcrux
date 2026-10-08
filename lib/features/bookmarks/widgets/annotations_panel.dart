import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/features/bookmarks/providers/annotation_reveal_request.dart';
import 'package:netcrux/features/bookmarks/widgets/annotation_dialog.dart';
import 'package:netcrux/features/bookmarks/widgets/bookmarks_panel.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';
import 'package:netcrux/shared/widgets/revealing_list_view.dart';

/// Panel listing the annotations of the active tab's design, docked as the
/// right dock's Annotations tab.
///
/// Mirrors [BookmarksPanel] in shape. Markdown bodies render via
/// `flutter_markdown_plus`'s [MarkdownBody]: paragraphs,
/// emphasis, links, code blocks, and lists all render natively. The edit
/// dialog still shows the raw markdown source for editing.
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
    final snapshot = ref.watch(bookmarkAnnotationSnapshotProvider);
    final annotations = snapshot.annotations;
    final revealId = ref.watch(annotationRevealRequestProvider);
    final revealIndex = revealId == null
        ? -1
        : annotations.indexWhere((a) => a.id == revealId);
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
                    itemCount: annotations.length,
                    revealIndex: revealIndex < 0 ? null : revealIndex,
                    onRevealed: revealId == null
                        ? null
                        : () => ref
                              .read(annotationRevealRequestProvider.notifier)
                              .acknowledge(revealId),
                    itemBuilder: (context, i, {required flashing}) =>
                        _AnnotationTile(
                          annotation: annotations[i],
                          flashing: flashing,
                        ),
                  ),
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
    return AnimatedContainer(
      key: ValueKey<String>('annotationRow-${annotation.id}'),
      duration: const Duration(milliseconds: 250),
      color: theme.colorScheme.primary.withValues(alpha: flashing ? 0.30 : 0),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: const Icon(Icons.sticky_note_2_outlined, size: 18),
        title: MarkdownBody(
          data: annotation.body,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(theme),
        ),
        subtitle: Text(
          '${bookmarkTargetKindLabel(l10n, annotation.targetKind)} · '
          '${annotation.targetId}'
          '${author != null ? ' · $author' : ''}',
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: PopupMenuButton<_AnnotationMenuAction>(
          icon: const Icon(Icons.more_horiz),
          onSelected: (action) async {
            final store = ref.read(bookmarkAnnotationStoreProvider);
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
      ),
    );
  }
}

enum _AnnotationMenuAction { edit, delete }
