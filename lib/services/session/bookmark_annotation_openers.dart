// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/bookmark.dart';

/// A pre-populated target for the Add Bookmark / Add Annotation dialogs.
///
/// When non-null, the opener mounts the dialog with the target fields
/// already filled in (commonly because the user invoked the action from
/// a schematic context menu on a specific element). When null, the
/// opener falls back to the active schematic selection.
@immutable
class BookmarkAnnotationTarget {
  /// Creates a target descriptor.
  const BookmarkAnnotationTarget({
    required this.kind,
    required this.targetId,
  });

  /// Which kind of schematic element this targets.
  final BookmarkTargetKind kind;

  /// The stable target id (cell instance name, pin `cell:port`,
  /// `port:<name>` for boundary ports, edge id `e_N` for nets, dotted
  /// scope path for scopes).
  final String targetId;
}

/// Opens the Add Bookmark dialog. When [target] is non-null the dialog
/// is pre-populated for that element; otherwise the opener resolves the
/// currently selected schematic element from the provided [ref].
///
/// The open-core default is a no-op so the action remains discoverable
/// in the command palette / menu bar even on Open Core builds where
/// no dialog is registered. The Pro overlay overrides this
/// provider with a callback that mounts the actual Add Bookmark dialog.
typedef AddBookmarkDialogOpener =
    void Function(
      BuildContext context,
      WidgetRef ref, {
      BookmarkAnnotationTarget? target,
    });

/// Opens the Add Annotation dialog. Same semantics as
/// [AddBookmarkDialogOpener].
typedef AddAnnotationDialogOpener =
    void Function(
      BuildContext context,
      WidgetRef ref, {
      BookmarkAnnotationTarget? target,
    });

/// Opens the Bookmarks panel (the side panel listing every bookmark in
/// the active session). Open-core default is a no-op; the Pro overlay
/// overrides with a callback that mounts the panel.
typedef BookmarksPanelOpener = void Function(BuildContext context);

/// Opens the Annotations panel. Same semantics as [BookmarksPanelOpener].
typedef AnnotationsPanelOpener = void Function(BuildContext context);

/// Open-core extension point through which the Pro overlay registers an
/// Add Bookmark dialog opener.
final addBookmarkDialogOpenerProvider = Provider<AddBookmarkDialogOpener>(
  (_) => (_, _, {target}) {
    // Open-core no-op. The Pro overlay overrides this with a callback
    // that mounts the Add Bookmark dialog.
  },
  name: 'addBookmarkDialogOpenerProvider',
);

/// Open-core extension point for the Add Annotation dialog opener.
final addAnnotationDialogOpenerProvider = Provider<AddAnnotationDialogOpener>(
  (_) => (_, _, {target}) {
    // Open-core no-op. The Pro overlay overrides this.
  },
  name: 'addAnnotationDialogOpenerProvider',
);

/// Open-core extension point for showing the Bookmarks panel.
final bookmarksPanelOpenerProvider = Provider<BookmarksPanelOpener>(
  (_) => (_) {
    // Open-core no-op. The Pro overlay overrides this.
  },
  name: 'bookmarksPanelOpenerProvider',
);

/// Open-core extension point for showing the Annotations panel.
final annotationsPanelOpenerProvider = Provider<AnnotationsPanelOpener>(
  (_) => (_) {
    // Open-core no-op. The Pro overlay overrides this.
  },
  name: 'annotationsPanelOpenerProvider',
);
