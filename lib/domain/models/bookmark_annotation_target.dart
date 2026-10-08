// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
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
