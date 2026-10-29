// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/file_open/file_open_service.dart';
import 'package:path/path.dart' as p;

/// What the Cell Libraries dialog applies: the tab's Liberty files and its
/// "show missing modules as black boxes" option.
typedef CellLibrariesEdit = ({
  List<String> libertyFiles,
  bool blackBoxMissingModules,
});

/// Opens the Cell Libraries dialog over [initial], the tab's Liberty files,
/// and [initialBlackBoxMissingModules], its black-box option, and returns
/// both as edited, or `null` when the user cancelled.
///
/// Files are added through [picker] and removed one by one; the list keeps
/// the order they were added in, which is the order elaboration reads them
/// (the first library to define a cell wins).
Future<CellLibrariesEdit?> showCellLibrariesDialog({
  required BuildContext context,
  required List<String> initial,
  required FileOpenService picker,
  bool initialBlackBoxMissingModules = false,
}) {
  return showCruxDialog<CellLibrariesEdit>(
    context: context,
    // An editor: closing is Cancel or Apply, never a stray scrim click.
    barrierDismissible: false,
    builder: (_) => CellLibrariesDialog(
      initial: initial,
      initialBlackBoxMissingModules: initialBlackBoxMissingModules,
      picker: picker,
    ),
  );
}

/// The Cell Libraries editor. Pops a [CellLibrariesEdit] on Apply.
class CellLibrariesDialog extends StatefulWidget {
  /// Creates the dialog over [initial].
  const CellLibrariesDialog({
    required this.initial,
    required this.picker,
    this.initialBlackBoxMissingModules = false,
    super.key,
  });

  /// The Liberty files the dialog opens with.
  final List<String> initial;

  /// Whether the black-box option is on when the dialog opens.
  final bool initialBlackBoxMissingModules;

  /// Picks the files Add adds.
  final FileOpenService picker;

  @override
  State<CellLibrariesDialog> createState() => _CellLibrariesDialogState();
}

class _CellLibrariesDialogState extends State<CellLibrariesDialog> {
  late final List<String> _files = List<String>.of(widget.initial);
  late bool _blackBoxes = widget.initialBlackBoxMissingModules;

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
    // CruxDialog scrolls its body as a whole when a short window cannot fit
    // the list, the Add button and the black-box option together.
    return CruxDialog(
      title: l10n.cellLibrariesDialogTitle,
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
            const SizedBox(height: 8),
            // For a design whose library is not at hand: the modules nothing
            // defines are drawn as black boxes instead of failing.
            CruxFormRow.checkbox(
              key: const ValueKey<String>('cellLibrariesBlackBoxes'),
              label: l10n.cellLibrariesDialogBlackBoxes,
              help: l10n.cellLibrariesDialogBlackBoxesHelp,
              value: _blackBoxes,
              onChanged: (value) => setState(() => _blackBoxes = value),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        CruxDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        CruxDialogAction(
          key: const ValueKey<String>('cellLibrariesApply'),
          label: l10n.cellLibrariesDialogApply,
          role: CruxDialogActionRole.primary,
          onPressed: () => Navigator.of(context).pop<CellLibrariesEdit>((
            libertyFiles: List<String>.of(_files),
            blackBoxMissingModules: _blackBoxes,
          )),
        ),
      ],
    );
  }
}
