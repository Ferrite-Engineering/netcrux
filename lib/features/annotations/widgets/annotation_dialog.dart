import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/features/annotations/providers/annotation_writing_provider.dart';
import 'package:netcrux/features/annotations/services/annotation_id_generator.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Opens the Add / Edit Annotation dialog and returns the resulting
/// [Annotation] (or `null` if the user cancelled).
///
/// The dialog has an optional one-line Title above the optional Markdown
/// Body; Save needs at least one of them. The title is what the
/// Annotations panel lists the annotation by.
///
/// On create ([existing] = `null`) the dialog mints a fresh id via
/// the [annotationIdGeneratorProvider]. On edit the dialog preserves
/// the existing id + createdAtMillis and bumps `updatedAtMillis` to
/// `DateTime.now().millisecondsSinceEpoch` so the panel can sort by
/// recency if it wants to. [moduleName], the module of the scope the
/// target was picked in, is recorded on create and kept on edit.
Future<Annotation?> showAnnotationDialog({
  required BuildContext context,
  required WidgetRef ref,
  required AnnotationTargetKind targetKind,
  required String targetId,
  String? moduleName,
  Annotation? existing,
}) {
  // While the dialog is open the room is told somebody is writing a note —
  // who, never what. Raised here, around the dialog, so every way of opening
  // it says so and every way of closing it stops saying so.
  final writing = ref.read(annotationWritingProvider.notifier)..start();
  return showDialog<Annotation>(
    context: context,
    // Editor dialogs hold in-progress user input: closing must be a
    // deliberate act (Cancel / Save), never a stray scrim click, as in every
    // other editor dialog in the suite. Note this
    // also disables Escape (Flutter routes DismissIntent through the
    // barrier flag).
    barrierDismissible: false,
    builder: (ctx) => _AnnotationDialog(
      ref: ref,
      targetKind: targetKind,
      targetId: targetId,
      moduleName: moduleName,
      existing: existing,
    ),
  ).whenComplete(writing.stop);
}

class _AnnotationDialog extends StatefulWidget {
  const _AnnotationDialog({
    required this.ref,
    required this.targetKind,
    required this.targetId,
    this.moduleName,
    this.existing,
  });

  final WidgetRef ref;
  final AnnotationTargetKind targetKind;
  final String targetId;
  final String? moduleName;
  final Annotation? existing;

  @override
  State<_AnnotationDialog> createState() => _AnnotationDialogState();
}

class _AnnotationDialogState extends State<_AnnotationDialog> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _author;
  late final String _initialTitle;
  late final String _initialBody;
  late final String _initialAuthor;

  /// Set when Save was pressed with neither a title nor a body; cleared by
  /// the next edit to either.
  bool _showEmptyError = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _initialTitle = existing?.title ?? '';
    _initialBody = existing?.body ?? '';
    _initialAuthor = existing?.author ?? '';
    _title = TextEditingController(text: _initialTitle);
    _body = TextEditingController(text: _initialBody);
    _author = TextEditingController(text: _initialAuthor);
    _title.addListener(_clearEmptyError);
    _body.addListener(_clearEmptyError);
  }

  void _clearEmptyError() {
    if (_showEmptyError) setState(() => _showEmptyError = false);
  }

  /// Whether any field differs from the values the dialog opened
  /// with. Clean forms close without a prompt; dirty ones confirm
  /// first (suite unsaved-changes canon — mirrors the Symbol Editor).
  bool get _isDirty =>
      _title.text != _initialTitle ||
      _body.text != _initialBody ||
      _author.text != _initialAuthor;

  Future<void> _onCancel() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final l10n = L10N.of(context);
    // Suite-standard destructive confirm: "Keep editing" in the cancel
    // slot, error-colored "Discard" verb. Any non-button dismissal
    // (scrim, Escape) resolves false, i.e. keeps editing, so
    // in-progress user input is never lost by a stray click.
    final confirmed = await confirmCruxDestructiveAction(
      context,
      title: l10n.annotationUnsavedChangesTitle,
      body: l10n.annotationUnsavedChangesBody,
      confirmLabel: l10n.annotationUnsavedChangesDiscard,
      cancelLabel: l10n.annotationUnsavedChangesKeep,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _author.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(
        isEdit ? l10n.annotationDialogEditTitle : l10n.annotationDialogTitle,
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const ValueKey<String>('annotationDialogTitleField'),
              controller: _title,
              decoration: InputDecoration(
                labelText: l10n.annotationDialogTitleLabel,
                hintText: l10n.annotationDialogTitleHint,
              ),
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey<String>('annotationDialogBodyField'),
              controller: _body,
              decoration: InputDecoration(
                labelText: l10n.annotationDialogBodyLabel,
                alignLabelWithHint: true,
                errorText: _showEmptyError
                    ? l10n.annotationDialogEmptyError
                    : null,
              ),
              minLines: 4,
              maxLines: 10,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _author,
              decoration: InputDecoration(
                labelText: l10n.annotationDialogAuthorLabel,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _onCancel,
          child: Text(l10n.annotationDialogCancelButton),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.annotationDialogSaveButton),
        ),
      ],
    );
  }

  void _submit() {
    final title = normalizeAnnotationTitle(_title.text);
    final body = _body.text.trim();
    if (title == null && body.isEmpty) {
      // Neither field says anything: say so in the form, and to a screen
      // reader, rather than ignoring the press.
      setState(() => _showEmptyError = true);
      announceCrux(context, L10N.of(context).annotationDialogEmptyError);
      return;
    }
    final author = _author.text.trim().isEmpty ? null : _author.text.trim();
    final existing = widget.existing;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Construct explicitly rather than with copyWith, which cannot express
    // "user cleared this field": a cleared title or author becomes null.
    // An edit keeps what the dialog does not show: the session the note was
    // written in, its author's frozen colour and attribution, and whether its
    // layer is hidden.
    final annotation = Annotation(
      id:
          existing?.id ??
          widget.ref.read(annotationIdGeneratorProvider).nextAnnotationId(),
      targetKind: widget.targetKind,
      targetId: widget.targetId,
      title: title,
      body: body,
      createdAtMillis: existing?.createdAtMillis ?? now,
      updatedAtMillis: now,
      author: author,
      moduleName: existing == null ? widget.moduleName : existing.moduleName,
      authorId: existing?.authorId,
      colorArgb: existing?.colorArgb,
      sessionLayerId: existing?.sessionLayerId,
      sessionLayerLabel: existing?.sessionLayerLabel,
      hidden: existing?.hidden ?? false,
    );
    Navigator.of(context).pop(annotation);
  }
}
