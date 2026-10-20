// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart' show announceCrux;
import 'package:crux_settings_ui/crux_settings_ui.dart' show CruxFormRow;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/annotations/providers/annotation_drafts_provider.dart';
import 'package:netcrux/features/annotations/services/annotation_actions.dart';
import 'package:netcrux/features/annotations/services/annotation_id_generator.dart';
import 'package:netcrux/features/annotations/services/annotations_on_scope.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/inspector/providers/inspector_providers.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';
import 'package:netcrux/services/telemetry/annotation_telemetry.dart';

/// The Inspector's annotations for one schematic element: an *Add
/// annotation* button, the new-annotation draft when one is started, and one
/// section per annotation on the element in the scope on screen.
///
/// Each of this participant's annotations is a form (title, body, author)
/// that applies on Apply; an annotation another participant of a
/// collaborative session wrote is shown as read-only rows, as the
/// Annotations panel offers it no Edit either.
///
/// Drafts live in the tab's [annotationDraftsProvider], so they outlast the
/// dock showing another tab. While any draft on this element holds unapplied
/// edits the Inspector keeps showing the element (reported through
/// [CruxInspector.markDirty], again on every mount).
class AnnotationInspectorSection extends ConsumerStatefulWidget {
  /// Creates the annotations of [element].
  const AnnotationInspectorSection({required this.element, super.key});

  /// The inspected element.
  final SelectedElement element;

  @override
  ConsumerState<AnnotationInspectorSection> createState() =>
      _AnnotationInspectorSectionState();
}

class _AnnotationInspectorSectionState
    extends ConsumerState<AnnotationInspectorSection> {
  @override
  void initState() {
    super.initState();
    // A section remounted over a kept draft (the dock showed another tab)
    // must hold the element again.
    CruxInspector.markDirty(
      context,
      dirty: _dirtyOn(ref.read(annotationDraftsProvider)),
    );
  }

  bool _dirtyOn(Map<String, AnnotationDraft> drafts) {
    final target = mapSelectionToAnnotationTarget(widget.element);
    if (target == null) return false;
    return drafts.values.any(
      (d) => d.isOn(target.kind, target.targetId) && d.isDirty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final target = mapSelectionToAnnotationTarget(widget.element);
    if (target == null) return const SizedBox.shrink();
    ref.listen<Map<String, AnnotationDraft>>(
      annotationDraftsProvider,
      (_, next) => CruxInspector.markDirty(context, dirty: _dirtyOn(next)),
    );
    final moduleName = ref.watch(hierarchyTreeProvider).selected?.moduleName;
    final annotations = annotationsOnElement(
      ref.watch(annotationSnapshotProvider).annotations,
      kind: target.kind,
      targetId: target.targetId,
      moduleName: moduleName,
    );
    final drafts = ref.watch(annotationDraftsProvider);
    final newKey = newAnnotationDraftKey(
      target.kind,
      target.targetId,
      moduleName,
    );
    final newDraft = drafts[newKey];
    // Somebody else's note: shown, never edited while their name is on it.
    // In a session "somebody else" is anyone but the local participant.
    final me = ref.watch(schematicCollabSessionProvider).value?.myParticipantId;

    final children = <Widget>[
      CruxInspectorSection(
        title: l10n.annotationsPanelTitle,
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey<String>('inspectorAddAnnotation'),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.annotationDialogTitle),
              onPressed: newDraft != null
                  ? null
                  : () {
                      final key = ref
                          .read(annotationDraftsProvider.notifier)
                          .startNew(
                            kind: target.kind,
                            targetId: target.targetId,
                            moduleName: moduleName,
                          );
                      ref
                          .read(inspectorFocusRequestProvider.notifier)
                          .request(key);
                    },
            ),
          ),
        ],
      ),
      if (newDraft != null)
        _AnnotationEditor(
          key: ValueKey<String>('annotationEditor-$newKey'),
          draftKey: newKey,
          annotation: null,
          seed: newDraft,
        ),
      for (final annotation in annotations)
        if (annotation.authorId != null && annotation.authorId != me)
          _ReadOnlyAnnotation(annotation: annotation)
        else
          _AnnotationEditor(
            key: ValueKey<String>('annotationEditor-${annotation.id}'),
            draftKey: annotation.id,
            annotation: annotation,
            seed: drafts[annotation.id] ?? AnnotationDraft.of(annotation),
          ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 16),
          children[i],
        ],
      ],
    );
  }
}

/// A section's heading for [annotation]: its title, the first line of its
/// body when untitled, or its element id when it has neither (the
/// Annotations panel's row heading).
String _headingOf(Annotation annotation) {
  final heading = annotation.heading;
  return heading.isEmpty ? annotation.targetId : heading;
}

class _ReadOnlyAnnotation extends StatelessWidget {
  const _ReadOnlyAnnotation({required this.annotation});

  final Annotation annotation;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final title = annotation.title;
    final author = annotation.author;
    return CruxInspectorSection(
      key: ValueKey<String>('annotationReadOnly-${annotation.id}'),
      title: _headingOf(annotation),
      children: <Widget>[
        if (title != null)
          CruxInspectorValueRow(
            label: l10n.annotationDialogTitleLabel,
            value: title,
          ),
        if (annotation.body.trim().isNotEmpty)
          CruxInspectorValueRow(
            label: l10n.annotationDialogBodyLabel,
            value: annotation.body,
          ),
        if (author != null)
          CruxInspectorValueRow(
            label: l10n.inspectorAnnotationAuthor,
            value: author,
          ),
      ],
    );
  }
}

/// One annotation's form: title, body and author, applied together.
class _AnnotationEditor extends ConsumerStatefulWidget {
  const _AnnotationEditor({
    required this.draftKey,
    required this.annotation,
    required this.seed,
    super.key,
  });

  /// The draft's key in [annotationDraftsProvider].
  final String draftKey;

  /// The annotation edited; null for a new one.
  final Annotation? annotation;

  /// The values the fields start from: the kept draft, else the
  /// annotation's own.
  final AnnotationDraft seed;

  @override
  ConsumerState<_AnnotationEditor> createState() => _AnnotationEditorState();
}

class _AnnotationEditorState extends ConsumerState<_AnnotationEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _author;
  final FocusNode _titleFocus = FocusNode(debugLabel: 'annotation title');

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.seed.title);
    _body = TextEditingController(text: widget.seed.body);
    _author = TextEditingController(text: widget.seed.author);
    _takeFocusRequest();
  }

  @override
  void didUpdateWidget(_AnnotationEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // With no draft kept, the fields follow the annotation (a collaborator's
    // update, an undo); a kept draft is the user's and stays.
    if (!ref.read(annotationDraftsProvider).containsKey(widget.draftKey)) {
      _sync(_title, widget.seed.title);
      _sync(_body, widget.seed.body);
      _sync(_author, widget.seed.author);
    }
  }

  static void _sync(TextEditingController controller, String text) {
    if (controller.text != text) controller.text = text;
  }

  /// Takes a pending focus request for this annotation. Consumed after the
  /// frame (no provider may change while the tree builds), and the title is
  /// focused a frame later still, so it wins over the Inspector's own
  /// open() focus on its first control.
  void _takeFocusRequest() {
    if (ref.read(inspectorFocusRequestProvider) != widget.draftKey) return;
    final binding = WidgetsBinding.instance;
    binding
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        if (!ref
            .read(inspectorFocusRequestProvider.notifier)
            .take(widget.draftKey)) {
          return;
        }
        binding
          ..addPostFrameCallback((_) {
            if (mounted) _titleFocus.requestFocus();
          })
          ..ensureVisualUpdate();
      })
      ..ensureVisualUpdate();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _author.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  AnnotationDraft get _draft =>
      ref.read(annotationDraftsProvider)[widget.draftKey] ?? widget.seed;

  void _edited() {
    final draft = _draft;
    final clearsError =
        draft.showEmptyError &&
        (_title.text != draft.title || _body.text != draft.body);
    ref
        .read(annotationDraftsProvider.notifier)
        .put(
          widget.draftKey,
          draft.copyWith(
            title: _title.text,
            body: _body.text,
            author: _author.text,
            showEmptyError: clearsError ? false : null,
          ),
        );
  }

  void _revert() {
    ref.read(annotationDraftsProvider.notifier).discard(widget.draftKey);
    final original = widget.annotation;
    if (original != null) {
      final seed = AnnotationDraft.of(original);
      _sync(_title, seed.title);
      _sync(_body, seed.body);
      _sync(_author, seed.author);
    }
  }

  void _apply() {
    final l10n = L10N.of(context);
    final title = normalizeAnnotationTitle(_title.text);
    final body = _body.text.trim();
    final drafts = ref.read(annotationDraftsProvider.notifier);
    if (title == null && body.isEmpty) {
      // Neither field says anything: say so in the form, and to a screen
      // reader, rather than ignoring the press.
      drafts.put(widget.draftKey, _draft.copyWith(showEmptyError: true));
      announceCrux(context, l10n.annotationDialogEmptyError);
      return;
    }
    final draft = _draft;
    final existing = widget.annotation;
    final author = _author.text.trim().isEmpty ? null : _author.text.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    // Constructed explicitly rather than with copyWith, which cannot express
    // "the user cleared this field": a cleared title or author becomes null.
    // An edit keeps what the form does not show: the session the note was
    // written in, its author's frozen colour and attribution, and whether its
    // layer is hidden.
    final annotation = Annotation(
      id:
          existing?.id ??
          ref.read(annotationIdGeneratorProvider).nextAnnotationId(),
      targetKind: draft.kind,
      targetId: draft.targetId,
      title: title,
      body: body,
      createdAtMillis: existing?.createdAtMillis ?? now,
      updatedAtMillis: now,
      author: author,
      moduleName: existing == null ? draft.moduleName : existing.moduleName,
      authorId: existing?.authorId,
      colorArgb: existing?.colorArgb,
      sessionLayerId: existing?.sessionLayerId,
      sessionLayerLabel: existing?.sessionLayerLabel,
      hidden: existing?.hidden ?? false,
    );
    final store = ref.read(annotationStoreProvider);
    if (existing == null) {
      store.addAnnotation(annotation);
      recordAnnotationAdded(ref.read(telemetryServiceProvider));
    } else {
      store.updateAnnotation(annotation);
    }
    drafts.discard(widget.draftKey);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    // The Annotations panel's Edit on an annotation already on screen.
    ref.listen<String?>(inspectorFocusRequestProvider, (_, next) {
      if (next == widget.draftKey) _takeFocusRequest();
    });
    final draft = ref.watch(
      annotationDraftsProvider.select((d) => d[widget.draftKey]),
    );
    final isNew = widget.annotation == null;
    final dirty = draft?.isDirty ?? false;
    final showError = draft?.showEmptyError ?? false;
    final existing = widget.annotation;
    return CruxInspectorSection(
      title: isNew ? l10n.inspectorNewAnnotation : _headingOf(existing!),
      onSubmit: dirty ? _apply : null,
      footer: CruxInspectorApplyBar(
        applyLabel: isNew
            ? l10n.annotationDialogTitle
            : l10n.annotationDialogSaveButton,
        revertLabel: isNew
            ? l10n.annotationUnsavedChangesDiscard
            : l10n.inspectorRevert,
        onApply: dirty ? _apply : null,
        onRevert: dirty ? _revert : null,
      ),
      children: <Widget>[
        CruxFormRow(
          label: l10n.annotationDialogTitleLabel,
          child: TextField(
            key: ValueKey<String>('annotationTitleField-${widget.draftKey}'),
            controller: _title,
            focusNode: _titleFocus,
            decoration: InputDecoration(
              hintText: l10n.annotationDialogTitleHint,
            ),
            onChanged: (_) => _edited(),
          ),
        ),
        CruxFormRow(
          label: l10n.annotationDialogBodyLabel,
          child: TextField(
            key: ValueKey<String>('annotationBodyField-${widget.draftKey}'),
            controller: _body,
            decoration: InputDecoration(
              errorText: showError ? l10n.annotationDialogEmptyError : null,
              errorMaxLines: 2,
            ),
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => _edited(),
          ),
        ),
        CruxFormRow(
          label: l10n.annotationDialogAuthorLabel,
          child: TextField(
            key: ValueKey<String>('annotationAuthorField-${widget.draftKey}'),
            controller: _author,
            onChanged: (_) => _edited(),
          ),
        ),
      ],
    );
  }
}
