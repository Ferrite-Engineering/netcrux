// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/file_open/file_open_service.dart';
import 'package:path/path.dart' as p;

/// Opens the Cell Libraries dialog over [initial], the tab's Liberty files,
/// and returns the edited list, or `null` when the user cancelled.
///
/// Files are added through [picker] and removed one by one; the list keeps
/// the order they were added in, which is the order elaboration reads them
/// (the first library to define a cell wins).
Future<List<String>?> showCellLibrariesDialog({
  required BuildContext context,
  required List<String> initial,
  required FileOpenService picker,
}) {
  return showDialog<List<String>>(
    context: context,
    // An editor: closing is Cancel or Apply, never a stray scrim click.
    barrierDismissible: false,
    builder: (_) => CellLibrariesDialog(initial: initial, picker: picker),
  );
}

/// The Cell Libraries list editor. Pops the edited list on Apply.
class CellLibrariesDialog extends StatefulWidget {
  /// Creates the dialog over [initial].
  const CellLibrariesDialog({
    required this.initial,
    required this.picker,
    super.key,
  });

  /// The Liberty files the dialog opens with.
  final List<String> initial;

  /// Picks the files Add adds.
  final FileOpenService picker;

  @override
  State<CellLibrariesDialog> createState() => _CellLibrariesDialogState();
}

class _CellLibrariesDialogState extends State<CellLibrariesDialog> {
  late final List<String> _files = List<String>.of(widget.initial);

  Future<void> _add() async {
    final l10n = L10N.of(context);
    final FileOpenResult result;
    try {
      result = await widget.picker.pickLibertyFiles(
        dialogTitle: l10n.filePickerLibertyDialogTitle,
      );
    } on Object catch (e) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.filePickerFailed('$e'));
      return;
    }
    if (result.isCancelled || !mounted) return;
    setState(() {
      for (final path in result.paths) {
        if (!_files.contains(path)) _files.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.cellLibrariesDialogTitle),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.cellLibrariesDialogBody,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_files.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.cellLibrariesDialogEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final path in _files)
                      ListTile(
                        key: ValueKey<String>('cellLibrary:$path'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.basename(path)),
                        subtitle: Text(
                          p.dirname(path),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: l10n.cellLibrariesDialogRemove(
                            p.basename(path),
                          ),
                          onPressed: () => setState(() => _files.remove(path)),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('cellLibrariesAdd'),
                icon: const Icon(Icons.add),
                label: Text(l10n.cellLibrariesDialogAdd),
                onPressed: _add,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey<String>('cellLibrariesApply'),
          onPressed: () => Navigator.of(context).pop(List<String>.of(_files)),
          child: Text(l10n.cellLibrariesDialogApply),
        ),
      ],
    );
  }
}
