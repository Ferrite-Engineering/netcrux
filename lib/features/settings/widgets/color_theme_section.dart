// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/help_urls.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Optional override for the `.crux-theme.json` install directory used
/// by the embedded [ThemePackBrowser]. Defaults to `{appSupportDir}/themes`.
typedef PackDirectoryResolver = Future<Directory> Function();

/// Settings → Appearance: drops `crux_theme`'s [ThemeAppearanceSection]
/// composer into NetCrux. Mirrors the WaveCrux adopter pattern —
/// activation flows through `cruxColorThemeProvider`, whose NetCrux
/// notifier override writes preset / token changes back to
/// `AppSettings.core.activeThemeName` + `core.themeOverrides`.
///
/// [ThemePackBrowser] takes storage as a [ThemePackStore] and exchanges
/// document *text* with its pickers, so `dart:io` stays on this side of
/// the seam. NetCrux supplies a [DirectoryThemePackStore] over the
/// resolved pack directory; tests may inject [store] directly (an
/// `InMemoryThemePackStore`) to keep both `path_provider` and the
/// desktop file picker out of the widget tree, or inject
/// [pickPackDocument] / [savePackDocument] to drive Import / Export.
class ColorThemeSection extends ConsumerStatefulWidget {
  /// Creates the Settings → Appearance section.
  const ColorThemeSection({
    this.store,
    this.packDirectoryResolver,
    this.pickPackDocument,
    this.savePackDocument,
    super.key,
  });

  /// Storage backing the installed-pack list. When null, a
  /// [DirectoryThemePackStore] is built over [packDirectoryResolver]'s
  /// directory.
  final ThemePackStore? store;

  /// Resolves the directory used by [ThemePackBrowser] for installed
  /// theme packs. Ignored when [store] is supplied.
  final PackDirectoryResolver? packDirectoryResolver;

  /// Optional override for the import picker. Defaults to a desktop
  /// `file_picker` invocation accepting `.json` files, whose contents
  /// are read and handed to the browser as text.
  final PickPackDocument? pickPackDocument;

  /// Optional override for the exporter. Defaults to a `file_picker`
  /// save dialog suggesting a `.crux-theme.json` name; returns the
  /// chosen path for the confirmation message.
  final SavePackDocument? savePackDocument;

  @override
  ConsumerState<ColorThemeSection> createState() => _ColorThemeSectionState();
}

class _ColorThemeSectionState extends ConsumerState<ColorThemeSection> {
  ThemePackStore? _store;

  @override
  void initState() {
    super.initState();
    final injected = widget.store;
    if (injected != null) {
      _store = injected;
      return;
    }
    unawaited(_resolveStore());
  }

  Future<void> _resolveStore() async {
    final resolver = widget.packDirectoryResolver ?? _defaultPackDirectory;
    Directory directory;
    try {
      directory = await resolver();
    } on Object {
      directory = Directory.systemTemp;
    }
    if (!mounted) return;
    setState(() => _store = DirectoryThemePackStore(directory: directory));
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store == null) {
      return const SizedBox(height: 24);
    }
    final theme = Theme.of(context);
    const strings = ThemeAppearanceStringsEn();
    final categories = ThemeRegistry.instance.registeredCategories;

    // Composed from the individual `crux_theme` widgets rather than the
    // bundled ThemeAppearanceSection composer, which renders its own
    // "Appearance" heading that would duplicate the Settings → Appearance
    // category title. Preset cards, token swatches, and pack rows are *data*,
    // so we pin every Card in this subtree to the value surface
    // (surfaceContainerHighest) to read distinctly from the section card.
    final dataSurface = theme.copyWith(
      cardTheme: theme.cardTheme.copyWith(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
    );

    return Theme(
      data: dataSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _SubsectionLabel(strings.presetSectionHeading),
                const SizedBox(width: 4),
                CruxHelpLink(
                  url: HelpUrls.appearanceAndThemes,
                  tooltip: L10N.of(context).helpLinkLearnMore,
                ),
              ],
            ),
            const SizedBox(height: 8),
            PresetPicker(presets: builtinPresets().values.toList()),
            const SizedBox(height: 20),
            _SubsectionLabel(strings.tokenOverridesSectionHeading),
            const SizedBox(height: 8),
            for (final category in categories)
              TokenCategorySection(category: category),
            const SizedBox(height: 20),
            _SubsectionLabel(strings.themePackBrowserSectionHeading),
            const SizedBox(height: 8),
            ThemePackBrowser(
              store: store,
              pickPackDocument:
                  widget.pickPackDocument ?? _defaultPickPackDocument,
              savePackDocument:
                  widget.savePackDocument ?? _defaultSavePackDocument,
            ),
          ],
        ),
      ),
    );
  }

  static Future<Directory> _defaultPackDirectory() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final dir = Directory(p.join(appSupport.path, 'themes'));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return dir;
    } on Object {
      return Directory.systemTemp;
    }
  }

  static Future<String?> _defaultPickPackDocument() async {
    final result = await FilePicker.pickFiles(
      allowedExtensions: ['json'],
      type: FileType.custom,
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    return await File(path).readAsString();
  }

  static Future<String?> _defaultSavePackDocument(String document) async {
    // file_picker 12 writes the file itself when given bytes, so the
    // encoded document goes straight to the chosen destination and the
    // returned path becomes the confirmation message's location.
    return await FilePicker.saveFile(
      bytes: Uint8List.fromList(utf8.encode(document)),
      fileName: 'netcrux-theme.crux-theme.json',
      allowedExtensions: ['json'],
      type: FileType.custom,
    );
  }
}

/// Label for a subsection inside Settings → Appearance (Presets / Color
/// overrides / Theme packs). Lighter than the Settings category title so the
/// hierarchy reads category → subsection → data.
class _SubsectionLabel extends StatelessWidget {
  const _SubsectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
