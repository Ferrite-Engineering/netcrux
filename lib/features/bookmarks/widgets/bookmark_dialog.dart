import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/features/bookmarks/services/bookmark_id_generator.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Riverpod provider exposing a per-app [BookmarkIdGenerator]. Tests
/// override this with a deterministic-clock generator so generated ids
/// are stable.
final bookmarkIdGeneratorProvider = Provider<BookmarkIdGenerator>(
  (_) => BookmarkIdGenerator(),
  name: 'bookmarkIdGeneratorProvider',
);

/// Opens the Add / Edit Bookmark dialog and returns the resulting
/// [Bookmark] (or `null` if the user cancelled).
///
/// On create ([existing] = `null`) the dialog mints a fresh id via
/// the [bookmarkIdGeneratorProvider] and records [moduleName], the module
/// of the scope the target was picked in. On edit ([existing] non-null)
/// the dialog reuses the existing id, createdAtMillis and module name and
/// only replaces the user-editable fields: the name and the note.
Future<Bookmark?> showBookmarkDialog({
  required BuildContext context,
  required WidgetRef ref,
  required BookmarkTargetKind targetKind,
  required String targetId,
  String? moduleName,
  Bookmark? existing,
}) {
  return showDialog<Bookmark>(
    context: context,
    // Editor dialogs hold in-progress user input: closing must be a
    // deliberate act (Cancel / Save), never a stray scrim click, as in every
    // other editor dialog in the suite. Note this
    // also disables Escape (Flutter routes DismissIntent through the
    // barrier flag).
    barrierDismissible: false,
    builder: (ctx) => _BookmarkDialog(
      ref: ref,
      targetKind: targetKind,
      targetId: targetId,
      moduleName: moduleName,
      existing: existing,
    ),
  );
}

class _BookmarkDialog extends StatefulWidget {
  const _BookmarkDialog({
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
  final Bookmark? existing;

  @override
  State<_BookmarkDialog> createState() => _BookmarkDialogState();
}

class _BookmarkDialogState extends State<_BookmarkDialog> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late final String _initialName;
  late final String _initialNote;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _initialName = existing?.name ?? '';
    _initialNote = existing?.note ?? '';
    _name = TextEditingController(text: _initialName);
    _note = TextEditingController(text: _initialNote);
  }

  /// Whether any field differs from the values the dialog opened with.
  /// Clean forms close without a prompt; dirty ones confirm first
  /// (suite unsaved-changes canon — mirrors the Symbol Editor).
  bool get _isDirty => _name.text != _initialName || _note.text != _initialNote;

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
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(
        isEdit ? l10n.bookmarkDialogEditTitle : l10n.bookmarkDialogTitle,
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.bookmarkDialogNameLabel,
              ),
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              decoration: InputDecoration(
                labelText: l10n.bookmarkDialogNoteLabel,
              ),
              minLines: 1,
              maxLines: 3,
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
    final name = _name.text.trim();
    if (name.isEmpty) return; // basic validation — name required
    final existing = widget.existing;
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    // Construct the bookmark explicitly rather than using copyWith —
    // copyWith uses `?? this.value` for nullable fields and can't
    // express "user cleared this field". On edit we re-emit every
    // field from the form; the id + createdAtMillis are preserved
    // from the existing entry.
    final bookmark = Bookmark(
      id:
          existing?.id ??
          widget.ref.read(bookmarkIdGeneratorProvider).nextBookmarkId(),
      name: name,
      targetKind: widget.targetKind,
      targetId: widget.targetId,
      createdAtMillis:
          existing?.createdAtMillis ?? DateTime.now().millisecondsSinceEpoch,
      note: note,
      moduleName: existing == null ? widget.moduleName : existing.moduleName,
    );
    Navigator.of(context).pop(bookmark);
  }
}
