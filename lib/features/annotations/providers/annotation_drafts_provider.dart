// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/features/annotations/providers/annotation_writing_provider.dart';

/// The key of the new-annotation draft on [kind] / [targetId] in a scope of
/// module [moduleName]. One new draft per element at a time.
String newAnnotationDraftKey(
  AnnotationTargetKind kind,
  String targetId,
  String? moduleName,
) => 'new:${kind.name}:${moduleName ?? ''}:$targetId';

/// An annotation being written or edited in the Inspector, not yet applied.
@immutable
class AnnotationDraft {
  /// Creates a draft. [existing] is the annotation being edited, or null for
  /// a new one.
  const AnnotationDraft({
    required this.kind,
    required this.targetId,
    required this.moduleName,
    required this.title,
    required this.body,
    required this.author,
    this.existing,
    this.showEmptyError = false,
  });

  /// A draft holding [annotation]'s current values.
  factory AnnotationDraft.of(Annotation annotation) => AnnotationDraft(
    kind: annotation.targetKind,
    targetId: annotation.targetId,
    moduleName: annotation.moduleName,
    title: annotation.title ?? '',
    body: annotation.body,
    author: annotation.author ?? '',
    existing: annotation,
  );

  /// The kind of element annotated.
  final AnnotationTargetKind kind;

  /// The element's canvas id.
  final String targetId;

  /// The module of the scope the element was picked in.
  final String? moduleName;

  /// The title field's text.
  final String title;

  /// The body field's text (Markdown).
  final String body;

  /// The author field's text.
  final String author;

  /// The annotation being edited; null for a new one.
  final Annotation? existing;

  /// Set when Apply was pressed with neither a title nor a body; cleared by
  /// the next edit of either.
  final bool showEmptyError;

  /// Whether the draft holds edits Apply would write. A new annotation is
  /// unapplied from the moment it is started.
  bool get isDirty {
    final e = existing;
    if (e == null) return true;
    return title != (e.title ?? '') ||
        body != e.body ||
        author != (e.author ?? '');
  }

  /// Whether this draft is on [kind] / [targetId].
  bool isOn(AnnotationTargetKind kind, String targetId) =>
      this.kind == kind && this.targetId == targetId;

  /// A copy with the given fields replaced.
  AnnotationDraft copyWith({
    String? title,
    String? body,
    String? author,
    bool? showEmptyError,
  }) => AnnotationDraft(
    kind: kind,
    targetId: targetId,
    moduleName: moduleName,
    title: title ?? this.title,
    body: body ?? this.body,
    author: author ?? this.author,
    existing: existing,
    showEmptyError: showEmptyError ?? this.showEmptyError,
  );
}

/// The Inspector's unapplied annotation drafts in this tab, keyed by the
/// annotation id (an edit) or [newAnnotationDraftKey] (a new one).
///
/// Per-tab (re-bound in `netcruxTabOverridesFactory`), and kept here rather
/// than in the section's widget state: the dock builds only its active tab,
/// so switching to the Annotations tab and back must not lose what was
/// typed.
///
/// While any draft is dirty this tab tells a collaborative session somebody
/// is writing a note ([annotationWritingProvider], who, never what), from
/// the first edit until the last draft is applied, reverted or the tab
/// closes.
final annotationDraftsProvider =
    NotifierProvider<AnnotationDraftsNotifier, Map<String, AnnotationDraft>>(
      AnnotationDraftsNotifier.new,
      name: 'annotationDraftsProvider',
    );

/// Notifier behind [annotationDraftsProvider].
class AnnotationDraftsNotifier extends Notifier<Map<String, AnnotationDraft>> {
  AnnotationWritingNotifier? _writing;
  bool _raised = false;

  @override
  Map<String, AnnotationDraft> build() {
    final writing = ref.read(annotationWritingProvider.notifier);
    _writing = writing;
    // No provider may be modified from inside onDispose, so the tab closing
    // with a draft open stops the presence just after.
    ref.onDispose(() {
      if (_raised) writing.stopLater();
      _raised = false;
    });
    return const <String, AnnotationDraft>{};
  }

  /// Starts a new annotation on [kind] / [targetId] and returns its key. An
  /// existing new draft on the same element is kept, not replaced.
  String startNew({
    required AnnotationTargetKind kind,
    required String targetId,
    required String? moduleName,
  }) {
    final key = newAnnotationDraftKey(kind, targetId, moduleName);
    if (!state.containsKey(key)) {
      _set(<String, AnnotationDraft>{
        ...state,
        key: AnnotationDraft(
          kind: kind,
          targetId: targetId,
          moduleName: moduleName,
          title: '',
          body: '',
          author: '',
        ),
      });
    }
    return key;
  }

  /// Records [draft] under [key]. An edit draft that matches its annotation
  /// again is dropped: nothing is left to apply.
  void put(String key, AnnotationDraft draft) {
    final next = Map<String, AnnotationDraft>.of(state);
    if (draft.existing != null && !draft.isDirty && !draft.showEmptyError) {
      next.remove(key);
    } else {
      next[key] = draft;
    }
    _set(next);
  }

  /// Drops the draft under [key] (applied or reverted).
  void discard(String key) {
    if (!state.containsKey(key)) return;
    _set(Map<String, AnnotationDraft>.of(state)..remove(key));
  }

  void _set(Map<String, AnnotationDraft> next) {
    state = Map<String, AnnotationDraft>.unmodifiable(next);
    final writing = next.values.any((d) => d.isDirty);
    if (writing == _raised) return;
    _raised = writing;
    if (writing) {
      _writing?.start();
    } else {
      _writing?.stop();
    }
  }
}
