// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the Custom Cell Symbol Manager screen.
///
/// Default is a no-op so [NetcruxAction.openSymbolManager] remains
/// discoverable in the command palette / menu bar on open-core
/// builds. The Pro overlay overrides this with a callback
/// that mounts the manager screen as a centered modal route.
typedef OpenSymbolManagerOpener = void Function(BuildContext context);

/// Prompts the user to choose an SVG file (via platform file picker)
/// and opens the Symbol Editor pre-loaded with its contents.
///
/// Default is a no-op. The Pro overlay overrides with a callback
/// that:
///
///   1. Opens the platform file picker for `*.svg`,
///   2. Sanitizes + validates the SVG content via the Pro registry's
///      SVG validator,
///   3. Opens the Symbol Editor with the parsed content and lets the
///      user pick the bound moduleType + adjust port anchors before
///      saving.
typedef ImportSymbolFromSvgOpener =
    void Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Opens the Symbol Editor for a specific module type. The Pro
/// overlay's opener creates a new symbol when none exists for
/// [moduleType] and opens it for editing when one does exist.
///
/// The context-menu dispatch invokes this directly with the
/// right-clicked cell's `cell.type`. The command-palette dispatch
/// falls back to the active selection's `cell.type` and surfaces a
/// snackbar when no cell is selected.
typedef EditSymbolForCurrentInstanceOpener =
    void Function(
      BuildContext context,
      WidgetRef ref, {
      String? moduleType,
    });

/// Removes the custom symbol bound to [moduleType] so subsequent
/// renders fall back to the built-in rectangular painter.
///
/// The Pro overlay's opener confirms with a small dialog before
/// deleting the on-disk file and emits a snackbar on completion.
typedef RemoveSymbolForCurrentInstanceOpener =
    void Function(
      BuildContext context,
      WidgetRef ref, {
      String? moduleType,
    });

/// Open-core extension point for opening the Symbol Manager.
final openSymbolManagerOpenerProvider = Provider<OpenSymbolManagerOpener>(
  (_) => (_) {
    // Open-core no-op. The Pro overlay overrides this.
  },
  name: 'openSymbolManagerOpenerProvider',
);

/// Open-core extension point for the "Import from SVG" entry.
final importSymbolFromSvgOpenerProvider = Provider<ImportSymbolFromSvgOpener>(
  (_) => (_, _) {
    // Open-core no-op. The Pro overlay overrides this.
  },
  name: 'importSymbolFromSvgOpenerProvider',
);

/// Open-core extension point for the "Edit Symbol for This Module"
/// entry (context-menu + palette).
final editSymbolForCurrentInstanceOpenerProvider =
    Provider<EditSymbolForCurrentInstanceOpener>(
      (_) => (_, _, {moduleType}) {
        // Open-core no-op. The Pro overlay overrides this.
      },
      name: 'editSymbolForCurrentInstanceOpenerProvider',
    );

/// Open-core extension point for the "Remove Custom Symbol" entry.
final removeSymbolForCurrentInstanceOpenerProvider =
    Provider<RemoveSymbolForCurrentInstanceOpener>(
      (_) => (_, _, {moduleType}) {
        // Open-core no-op. The Pro overlay overrides this.
      },
      name: 'removeSymbolForCurrentInstanceOpenerProvider',
    );
