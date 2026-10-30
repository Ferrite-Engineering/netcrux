// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/services/go_to_source_in_editor.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/host_bridge/editor_host_providers.dart';

/// Builds the "Go to Source in Editor" entry for the schematic context menu.
///
/// It exists only when an editor hosts the viewer: that editor is where the
/// RTL is, so the entry shows a source location there and needs no source
/// pane of NetCrux's own. In the standalone app and in a browser the builder
/// returns no entry.
///
/// The entry is shown even for an element whose netlist records no source, so
/// the menu does not change shape from one element to the next; choosing it
/// then says why nothing opened.
List<SchematicContextMenuExtensionEntry> buildEditorHostMenuEntries(
  WidgetRef ref,
  SelectedElement target,
) {
  if (!ref.read(isEditorHostedProvider)) {
    return const <SchematicContextMenuExtensionEntry>[];
  }
  final l10n = L10N.of(ref.context);
  return <SchematicContextMenuExtensionEntry>[
    SchematicContextMenuExtensionEntry(
      id: 'editor-go-to-source',
      label: l10n.goToSourceInEditor,
      onTap: (context, ref, _) async {
        if (!context.mounted) return;
        goToSourceInEditor(context, ref, target);
      },
    ),
  ];
}
