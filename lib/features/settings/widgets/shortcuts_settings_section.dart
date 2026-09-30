// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

// The package exports its own resolveShortcutConflicts; hide it so NetCrux's
// wrapper (shortcut_conflicts.dart), which supplies NetCrux's defaults and
// declaration order, is the one in scope.
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_keybindings/crux_keybindings.dart'
    hide resolveShortcutConflicts;
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/shortcuts/action_category.dart';
import 'package:netcrux/core/shortcuts/keymap_presets.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:netcrux/core/shortcuts/shortcut_conflicts.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Settings → Keyboard Shortcuts detail content: the editable, per-category
/// shortcut list with key capture, conflict detection, unbind, reset (one /
/// all), and `.crux-keymap` Import / Export.
///
/// Thin NetCrux wrapper over the cross-suite `KeyBindingsEditor`. NetCrux is a
/// desktop-first tool with no `MobileMetrics`, so it supplies a constant
/// sizing bundle.
class ShortcutsSettingsSection extends ConsumerStatefulWidget {
  /// Creates the section. The two pick callbacks are injectable so widget tests
  /// can drive Export / Import without the platform file-picker plugin.
  const ShortcutsSettingsSection({
    this.pickExportLocation,
    this.pickImportFile,
    super.key,
  });

  /// Chooses a destination file for Export. Defaults to a `saveFile` picker.
  final Future<File?> Function()? pickExportLocation;

  /// Chooses a `.crux-keymap` file for Import. Defaults to an open picker.
  final Future<File?> Function()? pickImportFile;

  @override
  ConsumerState<ShortcutsSettingsSection> createState() =>
      _ShortcutsSettingsSectionState();
}

class _ShortcutsSettingsSectionState
    extends ConsumerState<ShortcutsSettingsSection> {
  // NetCrux is desktop-first; a fixed sizing bundle is sufficient.
  static const _metrics = KeyBindingEditorMetrics(
    touchTarget: 40,
    iconSize: 20,
    bodyFontSize: 14,
    labelFontSize: 12,
    monoFontSize: 13,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final bindings = ref.watch(shortcutBindingsProvider);
    final notifier = ref.read(shortcutBindingsProvider.notifier);

    // Resolve precedence once: the editor's asymmetric per-row warnings and
    // summary banner are driven by the same pass that decides which action
    // actually fires (ShortcutManagerWidget), so the UI can never disagree with
    // runtime behavior.
    final resolution = resolveShortcutConflicts(bindings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetSelector(
          active: presetForBindings(bindings),
          onSelect: (preset) => notifier.applyPreset(bindingsForPreset(preset)),
        ),
        KeyBindingsEditor<NetcruxAction>(
          actions: NetcruxAction.values,
          categoryOf: (a) => a.category,
          categoryLabelOf: (c) => c.label(l10n),
          labelOf: (a) => a.label(l10n),
          bindings: bindings,
          defaults: defaultBindings(),
          conflicts: const {},
          conflictDetails: resolution.conflicts,
          conflictMessages: _NetCruxConflictMessages(l10n),
          metrics: _metrics,
          strings: _NetCruxKeyBindingsStrings(l10n),
          accessibilityStrings: _NetCruxKeyBindingsAccessibilityStrings(l10n),
          // `crux_keybindings` no longer depends on `crux_settings_ui`, so the
          // per-category container comes from the host. NetCrux uses the same
          // card every other Settings section is built from.
          categoryCardBuilder: (context, rows) =>
              CruxSettingsCard(children: rows),
          onCapture: (action, binding) =>
              notifier.setBinding(action, binding.materialize()),
          onUnbind: notifier.unbind,
          onReset: notifier.reset,
          onResetAll: notifier.resetAll,
          onImport: _import,
          onExport: _export,
        ),
      ],
    );
  }

  Future<void> _export() async {
    final l10n = L10N.of(context);
    final diffs = ref.read(shortcutBindingsProvider.notifier).currentDiffs();
    final content = netCruxKeymapCodec.encodeToString(diffs);
    try {
      final file =
          await (widget.pickExportLocation ?? _defaultPickExportLocation)();
      if (file == null) return;
      await file.writeAsString(content);
      if (!mounted) return;
      showCruxInfoSnack(context, l10n.settingsShortcutExportSuccess);
    } on Object catch (error) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.settingsShortcutExportFailure('$error'));
    }
  }

  Future<void> _import() async {
    final l10n = L10N.of(context);
    final notifier = ref.read(shortcutBindingsProvider.notifier);
    try {
      final file = await (widget.pickImportFile ?? _defaultPickImportFile)();
      if (file == null) return;
      final content = await file.readAsString();
      final diffs = netCruxKeymapCodec.decodeString(content);
      if (!mounted) return;
      if (diffs.isEmpty) {
        showCruxInfoSnack(context, l10n.settingsShortcutImportEmpty);
        return;
      }
      notifier.importDiffs(diffs);
      showCruxInfoSnack(
        context,
        l10n.settingsShortcutImportSuccess(diffs.length),
      );
    } on KeymapSchemaVersionException catch (error) {
      // A forward-version keymap is a different failure from a corrupt
      // one: nothing is wrong with the file, this build is simply older.
      // Saying "invalid file" would send the user to fix a good keymap.
      if (!mounted) return;
      showCruxErrorSnack(
        context,
        l10n.settingsShortcutImportNewerVersion(error.version),
      );
    } on Object catch (error) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.settingsShortcutImportFailure('$error'));
    }
  }

  static Future<File?> _defaultPickExportLocation() async {
    final path = await FilePicker.saveFile(
      // file_picker 12 requires bytes & writes the file; pass empty so it
      // only returns the chosen path and the editor writes via its own codec.
      bytes: Uint8List(0),
      fileName: 'netcrux.crux-keymap.json',
      allowedExtensions: ['json'],
      type: FileType.custom,
    );
    return path == null ? null : File(path);
  }

  static Future<File?> _defaultPickImportFile() async {
    final result = await FilePicker.pickFiles(
      allowedExtensions: ['json'],
      type: FileType.custom,
    );
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }
}

/// The keymap-preset chooser shown above the editable shortcut list. Selecting
/// a preset replaces all bindings; once the user hand-edits a row the active
/// preset reads as "Custom" (the `null` case, surfaced via the dropdown `hint`
/// so the user can land on it by editing but can never select it directly).
class _PresetSelector extends StatelessWidget {
  const _PresetSelector({required this.active, required this.onSelect});

  /// The preset the current bindings exactly match, or `null` for "Custom".
  final KeymapPreset? active;

  /// Invoked with the chosen preset (never called for the "Custom" item).
  final void Function(KeymapPreset preset) onSelect;

  String _label(KeymapPreset preset, L10N l10n) => switch (preset) {
    KeymapPreset.netCrux => l10n.settingsShortcutsPresetNetCrux,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return ListTile(
      title: Text(l10n.settingsShortcutsPresetLabel),
      subtitle: Text(l10n.settingsShortcutsPresetDescription),
      // `active == null` ("Custom") has no item — it is surfaced via [hint], so
      // the user can never *select* Custom, only land on it by hand-editing.
      trailing: DropdownButton<KeymapPreset>(
        value: active,
        hint: Text(l10n.settingsShortcutsPresetCustom),
        onChanged: (preset) {
          if (preset != null) onSelect(preset);
        },
        items: [
          for (final preset in KeymapPreset.values)
            DropdownMenuItem<KeymapPreset>(
              value: preset,
              child: Text(_label(preset, l10n)),
            ),
        ],
      ),
    );
  }
}

/// Adapts NetCrux's [L10N] to the package's [KeyBindingsEditorStrings].
class _NetCruxKeyBindingsStrings implements KeyBindingsEditorStrings {
  const _NetCruxKeyBindingsStrings(this._l10n);

  final L10N _l10n;

  @override
  String get description => _l10n.settingsShortcutsDescription;
  // NetCrux is desktop-first; the phone note is never shown (showPhoneNote
  // defaults to false), so an empty string is fine.
  @override
  String get phoneNote => '';
  @override
  String get importLabel => _l10n.settingsShortcutsImport;
  @override
  String get exportLabel => _l10n.settingsShortcutsExport;
  @override
  String get resetAllLabel => _l10n.settingsShortcutsResetAll;
  @override
  String get notBound => _l10n.settingsShortcutNotBound;
  @override
  String get editTooltip => _l10n.settingsShortcutEditTooltip;
  @override
  String get unbindTooltip => _l10n.settingsShortcutUnbindTooltip;
  @override
  String get resetTooltip => _l10n.settingsShortcutResetTooltip;
  @override
  String get capturePrompt => _l10n.settingsShortcutCapturePrompt;
  @override
  String conflict(String actions) => _l10n.settingsShortcutConflict(actions);
  @override
  String get resetAllTitle => _l10n.settingsShortcutResetAllTitle;
  @override
  String get resetAllBody => _l10n.settingsShortcutResetAllBody;
  @override
  String get resetAllCancel => _l10n.settingsShortcutResetAllCancel;
}

/// Adapts NetCrux's [L10N] to the package's keyboard hint and the spoken
/// form of an unbound row.
class _NetCruxKeyBindingsAccessibilityStrings
    implements KeyBindingsAccessibilityStrings {
  const _NetCruxKeyBindingsAccessibilityStrings(this._l10n);

  final L10N _l10n;

  @override
  String get keyboardHint => _l10n.settingsShortcutsKeyboardHint;
  @override
  String get notBoundSpoken => _l10n.settingsShortcutNotBoundSpoken;
}

/// Adapts NetCrux's [L10N] onto the package's asymmetric-conflict message
/// builders (the winning row, a shadowed row, and the summary banner).
class _NetCruxConflictMessages implements KeyBindingsConflictMessages {
  const _NetCruxConflictMessages(this._l10n);

  final L10N _l10n;

  @override
  String wins(String others) => _l10n.settingsShortcutConflictWins(others);

  @override
  String shadowedBy(String winner) =>
      _l10n.settingsShortcutConflictShadowed(winner);

  @override
  String summary(int count) => _l10n.settingsShortcutConflictSummary(count);
}
