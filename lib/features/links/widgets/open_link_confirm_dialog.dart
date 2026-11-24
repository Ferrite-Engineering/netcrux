// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:netcrux/features/links/services/netcrux_link_handler.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/links/netcrux_link.dart';
import 'package:path/path.dart' as p;

/// Asks whether to open a file a `netcrux://` link named, when the user has
/// not opened that file in NetCrux before.
///
/// Names the file twice: its base name in the sentence, and the full path the
/// link resolved to, which is the file that will be opened. Focus starts on
/// **Cancel**, so Enter or Space on arrival opens nothing, and Escape, like
/// Cancel, opens nothing. The answer is not stored anywhere.
class OpenLinkConfirmDialog extends StatelessWidget {
  /// Creates the dialog for the resolved [path].
  const OpenLinkConfirmDialog({required this.path, super.key});

  /// The file the link resolved to.
  final String path;

  /// Shows the dialog over [context] and resolves true only when the user
  /// chose Open.
  static Future<bool> show(BuildContext context, String path) async {
    final result = await showCruxDialog<bool>(
      context: context,
      barrierDismissible: false,
      modalGuardKey: 'netcruxLinkConfirm',
      builder: (_) => OpenLinkConfirmDialog(path: path),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    return CruxDialog(
      title: l10n.linkConfirmTitle,
      width: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.linkConfirmBody(p.basename(path))),
          const SizedBox(height: 12),
          Text(l10n.linkConfirmPathLabel, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            path,
            key: const ValueKey('linkConfirmPath'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
      actions: [
        CruxDialogAction(
          key: const ValueKey('linkConfirmCancel'),
          label: l10n.linkConfirmCancel,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        CruxDialogAction(
          key: const ValueKey('linkConfirmOpen'),
          label: l10n.linkConfirmOpen,
          role: CruxDialogActionRole.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// The message to show for [outcome], and whether it reports an error; null
/// when there is nothing to say (the design opened as asked, or the user
/// cancelled).
({String message, bool error})? netCruxLinkOutcomeMessage(
  L10N l10n,
  NetCruxLinkOutcome outcome,
) {
  final name = outcome.fileName ?? '';
  switch (outcome.failure) {
    case NetCruxLinkFailure.malformed:
      return (message: l10n.linkRefusedMalformed, error: true);
    case NetCruxLinkFailure.pathRefused:
      return (message: l10n.linkRefusedPath, error: true);
    case NetCruxLinkFailure.notADesign:
      return (message: l10n.linkRefusedNotDesign(name), error: true);
    case NetCruxLinkFailure.fileNotFound:
      return (message: l10n.linkRefusedNotFound(name), error: true);
    case NetCruxLinkFailure.loadFailed:
      return (message: l10n.linkRefusedLoadFailed(name), error: true);
    case null:
      break;
  }
  final path = outcome.path;
  if (!outcome.opened || path == null || !outcome.elementNotFound) return null;
  final opened = p.basename(path);
  final element = _bounded(outcome.name ?? '');
  return switch (outcome.kind) {
    NetCruxLinkElementKind.net => (
      message: l10n.linkNetNotFound(opened, element),
      error: false,
    ),
    _ => (message: l10n.linkCellNotFound(opened, element), error: false),
  };
}

/// A link chose this text, so it is shortened before it reaches the screen.
String _bounded(String text) =>
    text.length <= 120 ? text : '${text.substring(0, 117)}...';
