import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/features/bookmarks/services/bookmark_target_reveal.dart';
import 'package:netcrux/features/bookmarks/widgets/bookmark_dialog.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';

/// Panel listing the bookmarks of the active tab's design, docked as the
/// right dock's Bookmarks tab.
///
/// Watches [bookmarkAnnotationSnapshotProvider], which the per-tab override
/// list re-binds, so the list rebuilds on every add / update / remove and
/// shows only the bookmarks made in this tab.
///
/// Each row is one focusable, named control: it reads the bookmark's name,
/// the kind and id of its element and, when it has one, the note, which
/// sighted users read in the row's tooltip. Activating a row (click, Enter
/// or Space) selects the element on the schematic and brings it into view.
class BookmarksPanel extends ConsumerWidget {
  /// Creates the panel.
  const BookmarksPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final snapshot = ref.watch(bookmarkAnnotationSnapshotProvider);
    final bookmarks = snapshot.bookmarks;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  l10n.bookmarksPanelTitle,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: bookmarks.isEmpty
                ? Center(
                    child: Text(
                      l10n.bookmarksPanelEmpty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: bookmarks.length,
                    itemBuilder: (_, i) =>
                        _BookmarkTile(bookmark: bookmarks[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BookmarkTile extends ConsumerWidget {
  const _BookmarkTile({required this.bookmark});
  final Bookmark bookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final note = bookmark.note;
    final hasNote = note != null && note.isNotEmpty;
    final kind = bookmarkTargetKindLabel(l10n, bookmark.targetKind);
    final label = hasNote
        ? l10n.bookmarksPanelRowSemanticsWithNote(
            bookmark.name,
            kind,
            bookmark.targetId,
            note,
          )
        : l10n.bookmarksPanelRowSemantics(
            bookmark.name,
            kind,
            bookmark.targetId,
          );
    final row = Semantics(
      container: true,
      button: true,
      label: label,
      onTap: () => _reveal(context, l10n),
      child: InkWell(
        key: ValueKey<String>('bookmarkRow-${bookmark.id}'),
        excludeFromSemantics: true,
        onTap: () => _reveal(context, l10n),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ExcludeSemantics(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              bookmark.name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          if (hasNote) ...<Widget>[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.notes,
                              key: ValueKey<String>(
                                'bookmarkNoteMarker-${bookmark.id}',
                              ),
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '$kind · ${bookmark.targetId}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Row(
      children: <Widget>[
        Expanded(
          // The note is the row's tooltip; the row's semantics label
          // already carries it, so the tooltip adds no second name.
          child: hasNote
              ? Tooltip(
                  message: note,
                  excludeFromSemantics: true,
                  waitDuration: const Duration(milliseconds: 400),
                  child: row,
                )
              : row,
        ),
        PopupMenuButton<_BookmarkMenuAction>(
          icon: const Icon(Icons.more_horiz),
          onSelected: (action) async {
            final store = ref.read(bookmarkAnnotationStoreProvider);
            switch (action) {
              case _BookmarkMenuAction.edit:
                final edited = await showBookmarkDialog(
                  context: context,
                  ref: ref,
                  targetKind: bookmark.targetKind,
                  targetId: bookmark.targetId,
                  existing: bookmark,
                );
                if (edited != null) store.updateBookmark(edited);
              case _BookmarkMenuAction.delete:
                store.removeBookmark(bookmark.id);
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<_BookmarkMenuAction>>[
            PopupMenuItem<_BookmarkMenuAction>(
              value: _BookmarkMenuAction.edit,
              child: Text(l10n.bookmarkContextMenuEdit),
            ),
            PopupMenuItem<_BookmarkMenuAction>(
              value: _BookmarkMenuAction.delete,
              child: Text(l10n.bookmarkContextMenuDelete),
            ),
          ],
        ),
      ],
    );
  }

  /// Selects and reveals the bookmark's element on this tab's schematic.
  /// The panel is mounted inside the tab's scope, so the container found
  /// here is the tab's.
  void _reveal(BuildContext context, L10N l10n) {
    final tab = ProviderScope.containerOf(context, listen: false);
    final found = revealBookmarkTarget(
      tab,
      kind: bookmark.targetKind,
      targetId: bookmark.targetId,
      moduleName: bookmark.moduleName,
    );
    if (!found) {
      showCruxInfoSnack(
        context,
        l10n.bookmarksPanelTargetNotFound(bookmark.name),
      );
    }
  }
}

/// The localized name of a bookmark or annotation target kind, as the
/// panels and the screen-reader labels show it.
String bookmarkTargetKindLabel(L10N l10n, BookmarkTargetKind kind) {
  switch (kind) {
    case BookmarkTargetKind.cell:
      return l10n.bookmarkTargetKindCell;
    case BookmarkTargetKind.port:
      return l10n.bookmarkTargetKindPort;
    case BookmarkTargetKind.boundaryPort:
      return l10n.bookmarkTargetKindBoundaryPort;
    case BookmarkTargetKind.net:
      return l10n.bookmarkTargetKindNet;
    case BookmarkTargetKind.scope:
      return l10n.bookmarkTargetKindScope;
  }
}

enum _BookmarkMenuAction { edit, delete }
