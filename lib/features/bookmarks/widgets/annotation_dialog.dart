import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/features/bookmarks/widgets/bookmark_dialog.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Opens the Add / Edit Annotation dialog and returns the resulting
/// [Annotation] (or `null` if the user cancelled).
///
/// On create ([existing] = `null`) the dialog mints a fresh id via
/// the [bookmarkIdGeneratorProvider]. On edit the dialog preserves
/// the existing id + createdAtMillis and bumps `updatedAtMillis` to
/// `DateTime.now().millisecondsSinceEpoch` so the panel can sort by
/// recency if it wants to. [moduleName], the module of the scope the
/// target was picked in, is recorded on create and kept on edit.
Future<Annotation?> showAnnotationDialog({
  required BuildContext context,
  required WidgetRef ref,
  required BookmarkTargetKind targetKind,
  required String targetId,
  String? moduleName,
  Annotation? existing,
}) {
  return showDialog<Annotation>(
    context: context,
    // Editor dialogs hold in-progress user input: closing must be a
    // deliberate act (Cancel / Save), never a stray scrim click — the
    // suite dialog canon (UI_CONSISTENCY_CHARTER.md §1.8). Note this
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
  );
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
  final BookmarkTargetKind targetKind;
  final String targetId;
  final String? moduleName;
  final Annotation? existing;

  @override
  State<_AnnotationDialog> createState() => _AnnotationDialogState();
}

class _AnnotationDialogState extends State<_AnnotationDialog> {
  late final TextEditingController _body;
  late final TextEditingController _author;
  late final String _initialBody;
  late final String _initialAuthor;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _initialBody = existing?.body ?? '';
    _initialAuthor = existing?.author ?? '';
    _body = TextEditingController(text: _initialBody);
    _author = TextEditingController(text: _initialAuthor);
  }

  /// Whether either field differs from the values the dialog opened
  /// with. Clean forms close without a prompt; dirty ones confirm
  /// first (suite unsaved-changes canon — mirrors the Symbol Editor).
  bool get _isDirty =>
      _body.text != _initialBody || _author.text != _initialAuthor;

  Future<void> _onCancel() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final l10n = L10N.of(context);
    // Suite-standard destructive confirm: "Keep editing" in the cancel
    // slot, error-colored "Discard" verb. Any non-button dismissal
    // (scrim, Escape) resolves false, i.e. keeps editing, so
    // in-progress user input is never lost by a stray click
    // (UI_CONSISTENCY_CHARTER.md §1.8).
    final confirmed = await confirmCruxDestructiveAction(
      context,
      title: l10n.bookmarkAnnotationUnsavedChangesTitle,
      body: l10n.bookmarkAnnotationUnsavedChangesBody,
      confirmLabel: l10n.bookmarkAnnotationUnsavedChangesDiscard,
      cancelLabel: l10n.bookmarkAnnotationUnsavedChangesKeep,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
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
              controller: _body,
              decoration: InputDecoration(
                labelText: l10n.annotationDialogBodyLabel,
                alignLabelWithHint: true,
              ),
              autofocus: true,
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
          child: Text(l10n.bookmarkDialogCancelButton),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.bookmarkDialogSaveButton),
        ),
      ],
    );
  }

  void _submit() {
    final body = _body.text.trim();
    if (body.isEmpty) return; // basic validation — body required
    final author = _author.text.trim().isEmpty ? null : _author.text.trim();
    final existing = widget.existing;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Same rationale as the bookmark dialog: construct explicitly to
    // express "user cleared the author field" → null.
    final annotation = Annotation(
      id:
          existing?.id ??
          widget.ref.read(bookmarkIdGeneratorProvider).nextAnnotationId(),
      targetKind: widget.targetKind,
      targetId: widget.targetId,
      body: body,
      createdAtMillis: existing?.createdAtMillis ?? now,
      updatedAtMillis: now,
      author: author,
      moduleName: existing == null ? widget.moduleName : existing.moduleName,
    );
    Navigator.of(context).pop(annotation);
  }
}
