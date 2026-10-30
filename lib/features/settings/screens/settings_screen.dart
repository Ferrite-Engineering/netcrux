// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_async/crux_async.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/help_urls.dart';
import 'package:netcrux/core/platform_utils.dart';
import 'package:netcrux/domain/enums/yosys_path_mode.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/settings/providers/extra_settings_categories_provider.dart';
import 'package:netcrux/features/settings/widgets/color_theme_section.dart';
import 'package:netcrux/features/settings/widgets/layout_cell_limit_tile.dart';
import 'package:netcrux/features/settings/widgets/settings_editors_section.dart';
import 'package:netcrux/features/settings/widgets/shortcuts_settings_section.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/yosys/yosys_unavailable_reason_text.dart';

/// Application settings screen (mobile/full-screen route).
///
/// On desktop platforms call [SettingsScreen.openAdaptive] instead — it
/// presents the same content inside a modal dialog so the workspace
/// stays visible behind it, matching standard desktop conventions
/// (Cmd+, on macOS, Ctrl+, on Linux/Windows).
///
/// Three sections:
///   - General: AutoReloadMode toggle.
///   - Appearance: color-preset picker (brightness follows the preset).
///   - Engines → Yosys: auto / bundled / custom selector, plus a
///     live-validated text field for the custom-path case.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  /// Opens settings in a dialog on desktop or as a pushed route on mobile,
  /// via the suite-shared shell (`crux_settings_ui`).
  ///
  /// [initialCategoryId] opens it at that category instead of the first: the
  /// licence-expiry strip opens Settings → License this way.
  static Future<void> openAdaptive(
    BuildContext context, {
    String? initialCategoryId,
  }) {
    final l10n = L10N.of(context);
    // Re-entrancy guard: Cmd/Ctrl+, auto-repeat, a double-tap on the menu
    // item, or the palette entry must not stack a second settings surface.
    // Guarded inside the opener so every caller is covered.
    return ModalGuard.run(
      'settings',
      () => openCruxSettings(
        context,
        title: l10n.settingsTitle,
        closeTooltip: l10n.settingsClose,
        asDialog: isDesktopPlatform,
        initialCategoryId: initialCategoryId,
        bodyBuilder: (_) => const _SettingsContent(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return CruxSettingsRouteShell(
      title: l10n.settingsTitle,
      closeTooltip: l10n.settingsClose,
      body: const _SettingsContent(),
    );
  }
}

// ── Settings body (shared master-detail shell) ────────────────────────────────

/// Builds the NetCrux category list and hands it to the shared
/// [CruxSettingsMasterDetail] shell (from `package:crux_settings_ui`). The
/// dialog / route chrome is the suite-shared shell (crux_settings_ui).
class _SettingsContent extends ConsumerWidget {
  const _SettingsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings.defaults();
    // Overlay-contributed categories (none in open-core), appended after the
    // built-ins via the suite-shared seam.
    final extras = ref
        .watch(extraSettingsCategoriesProvider)
        .map((extra) => extra.toCategory(context))
        .toList();
    // Privacy holds the telemetry toggle and nothing else, so it is offered
    // only on a build whose pipeline can actually transmit. During the beta
    // with no dev flag the Settings screen is exactly what it was before
    // telemetry existed — telemetry's dark launch, extended to the UI.
    final showPrivacySection = ref.watch(telemetryConsentUiVisibleProvider);
    return CruxSettingsMasterDetail(
      categories: [
        ..._categories(
          l10n,
          settings,
          showPrivacySection: showPrivacySection,
        ),
        ...extras,
      ],
    );
  }

  List<CruxSettingsCategory> _categories(
    L10N l10n,
    AppSettings settings, {
    required bool showPrivacySection,
  }) {
    final core = settings.core;
    return [
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.general,
        icon: Icons.tune,
        title: l10n.settingsGeneralSection,
        content: CruxSettingsCard(
          children: [
            _AutoReloadModeTile(currentMode: core.autoReloadMode),
            _RestoreTabsOnLaunchTile(enabled: core.restoreTabsOnLaunch),
            _AutoCheckUpdatesTile(enabled: settings.autoCheckForUpdates),
            // Debug and profile builds force the surfaces on, so the toggle
            // would be inert there.
            if (kReleaseMode)
              _DiagnosticsEnabledTile(enabled: core.diagnosticsEnabled),
          ],
        ),
      ),
      // Appearance holds only the color-preset picker: brightness follows
      // the active preset (the WaveCrux model, which has no standalone
      // System/Light/Dark mode selector).
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.appearance,
        icon: Icons.palette_outlined,
        title: l10n.settingsAppearanceSection,
        content: CruxSettingsCard(
          children: [
            // The shared suite Language picker — the four shipped locales
            // were unreachable in NetCrux before this (no picker, and the
            // persisted CoreSettings.locale was never applied).
            _LanguageTile(locale: core.locale),
            const ColorThemeSection(),
          ],
        ),
      ),
      // Privacy sits third — as high as the suite-canonical "General leads,
      // then Appearance" ordering allows. It holds the telemetry opt-out, and
      // the promise is that the off switch is not buried; a section
      // the user has to hunt down a rail for is buried. Offered only when this
      // build can transmit at all.
      //
      // The section itself is `crux_telemetry`'s, so all four products' opt-out
      // is one implementation; only the category placement and the localized
      // heading are NetCrux's.
      if (showPrivacySection)
        CruxSettingsCategory(
          id: CruxSettingsCategoryId.privacy,
          icon: Icons.privacy_tip_outlined,
          title: l10n.settingsPrivacySection,
          content: const TelemetrySettingsSection(),
        ),
      // `productDefaults` is the suite's third-rail slot for "whatever this
      // product's own defaults are". NetCrux titles it Engines (the Yosys
      // binary); the other three title the same id differently. One id, four
      // titles — the suite fixes the slot, not the wording.
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.productDefaults,
        icon: Icons.memory,
        title: l10n.settingsEnginesSection,
        content: CruxSettingsCard(
          children: [
            _YosysPathModeTile(currentMode: settings.yosysPathMode),
            if (settings.yosysPathMode == YosysPathMode.custom)
              _YosysCustomPathTile(currentPath: settings.yosysCustomPath),
            LayoutCellLimitTile(currentLimit: settings.layoutCellLimit),
          ],
        ),
      ),
      // Dedicated Editors section: the editor-command field is
      // cross-feature config, not a CXP setting, so it lives in its own
      // section in every Crux app.
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.editors,
        icon: Icons.edit_outlined,
        title: l10n.settingsEditorsSection,
        content: SettingsEditorsSection(
          currentCommand: settings.cxpEditorCommand,
        ),
      ),
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.cxp,
        // hub_outlined is the suite's CXP icon (wifi_tethering is WaveCrux's
        // WCP Remote Control); the old key was also literally named
        // "RemoteControl" while its value read "CXP Cross-Probe".
        icon: Icons.hub_outlined,
        title: l10n.settingsCxpSectionTitle,
        content: const CruxSettingsSectionCard(
          children: [
            // The suite-shared CXP section (crux_cxp_ui), bound to the shared
            // lifecycle: the four controls and the status line.
            CruxCxpSettingsSection(),
            _CxpHelpRow(),
          ],
        ),
      ),
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.shortcuts,
        icon: Icons.keyboard_outlined,
        title: l10n.settingsShortcutsSection,
        content: const ShortcutsSettingsSection(),
      ),
    ];
  }
}

class _LanguageTile extends ConsumerWidget {
  const _LanguageTile({required this.locale});
  final String locale;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return CruxLocaleSettingTile(
      label: l10n.settingsLanguageLabel,
      description: l10n.settingsLanguageDescription,
      locale: locale,
      onChanged: (v) =>
          unawaited(ref.read(appSettingsProvider.notifier).setLocale(v)),
    );
  }
}

class _AutoReloadModeTile extends ConsumerWidget {
  const _AutoReloadModeTile({required this.currentMode});
  final AutoReloadMode currentMode;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    // The suite-shared control: segmented prompt / auto / off in canonical
    // order (this app previously led with auto).
    return CruxAutoReloadSettingTile(
      label: l10n.settingsAutoReloadLabel,
      description: l10n.settingsAutoReloadDescription,
      value: currentMode,
      onChanged: (mode) => unawaited(
        ref.read(appSettingsProvider.notifier).setAutoReloadMode(mode),
      ),
      promptLabel: l10n.settingsAutoReloadPrompt,
      autoLabel: l10n.settingsAutoReloadAuto,
      offLabel: l10n.settingsAutoReloadOff,
    );
  }
}

class _YosysPathModeTile extends ConsumerWidget {
  const _YosysPathModeTile({required this.currentMode});
  final YosysPathMode currentMode;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    // The same row a [CruxSettingsControlTile] builds, but not merged into one
    // semantics node: the control is wrapped beside a help link, so a merged
    // row would flatten the segments and the link into a single node.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: CruxFormRow(
        label: l10n.settingsYosysPathLabel,
        mergeSemantics: false,
        // The help icon rides the control row (the label is a plain string),
        // pointing at the docs' "How Yosys is used under the hood".
        child: Row(
          children: [
            Expanded(
              child: CruxSegmentedControl<YosysPathMode>(
                segments: <CruxSegment<YosysPathMode>>[
                  CruxSegment<YosysPathMode>(
                    value: YosysPathMode.autoDetect,
                    label: l10n.yosysPathModeAuto,
                  ),
                  CruxSegment<YosysPathMode>(
                    value: YosysPathMode.custom,
                    label: l10n.yosysPathModeCustom,
                  ),
                ],
                // No Bundled segment: no Yosys binary ships with NetCrux, so it
                // would resolve exactly as Auto-detect does. A setting saved as
                // Bundled still resolves that way and shows as Auto-detect.
                selected: currentMode == YosysPathMode.bundled
                    ? YosysPathMode.autoDetect
                    : currentMode,
                semanticLabel: l10n.settingsYosysPathLabel,
                onChanged: (mode) => unawaited(
                  ref.read(appSettingsProvider.notifier).setYosysPathMode(mode),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CruxHelpLink(
              url: HelpUrls.gettingStarted,
              tooltip: l10n.helpLinkLearnMore,
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom Yosys path field with live `yosys -V` validation.
///
/// Debounces the user's typing (400 ms) before probing the executable
/// so we don't fork a subprocess on every keystroke; surfaces the
/// detected version below the field or an error message when the
/// path is invalid.
class _YosysCustomPathTile extends ConsumerStatefulWidget {
  const _YosysCustomPathTile({required this.currentPath});
  final String currentPath;

  @override
  ConsumerState<_YosysCustomPathTile> createState() =>
      _YosysCustomPathTileState();
}

class _YosysCustomPathTileState extends ConsumerState<_YosysCustomPathTile> {
  late final TextEditingController _controller;
  final Debouncer _debouncer = Debouncer(
    duration: const Duration(milliseconds: 400),
  );
  YosysAvailability? _probe;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPath);
    if (widget.currentPath.isNotEmpty) {
      _scheduleProbe(widget.currentPath, immediate: true);
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleProbe(String path, {bool immediate = false}) {
    _debouncer.cancel();
    if (path.isEmpty) {
      setState(() {
        _probe = null;
        _probing = false;
      });
      return;
    }
    setState(() => _probing = true);
    _debouncer.run(() => unawaited(_probe_(path)));
    // A path already saved is probed as the tile opens, not 400 ms later.
    if (immediate) _debouncer.flush();
  }

  Future<void> _probe_(String path) async {
    final service = YosysAvailabilityService(executableNameOverride: path);
    final result = await service.probe();
    if (!mounted) return;
    setState(() {
      _probe = result;
      _probing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final probe = _probe;
    Widget? helper;
    if (_probing) {
      helper = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(l10n.yosysCustomPathProbing),
          ],
        ),
      );
    } else if (probe != null) {
      if (probe.isAvailable) {
        helper = Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            l10n.yosysCustomPathDetected(probe.versionString ?? ''),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.tertiary,
            ),
          ),
        );
      } else {
        // A path that stalled on a network mount is not an invalid path,
        // and the fix is different; name the reason when the probe
        // reports one this build models.
        final reason = yosysUnavailableReasonText(
          l10n,
          probe.unavailableReason,
        );
        helper = Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            reason ?? l10n.yosysCustomPathInvalid,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CruxFormRow(
            label: l10n.settingsYosysCustomPathLabel,
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: l10n.settingsYosysCustomPathHint,
              ),
              onChanged: (value) {
                unawaited(
                  ref
                      .read(appSettingsProvider.notifier)
                      .setYosysCustomPath(value),
                );
                _scheduleProbe(value);
              },
            ),
          ),
          ?helper,
        ],
      ),
    );
  }
}

/// Settings → General switch for the persisted automatic update check.
///
/// Keyed so the widget test can find the switch without depending on the
/// localized label. Turning it off suppresses only the automatic (launch /
/// periodic / on-resume) checks — the manual "Check for Updates" action still
/// runs, which is why the subtitle names what the check transmits rather than
/// promising the app never reaches the network.
class _AutoCheckUpdatesTile extends ConsumerWidget {
  const _AutoCheckUpdatesTile({required this.enabled});

  /// Widget key of the toggle, so tests can drive it locale-independently.
  static const Key switchKey = Key('settingsAutoCheckUpdatesSwitch');

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: CruxFormRow.toggle(
        key: switchKey,
        label: l10n.settingsAutoCheckUpdatesLabel,
        help: l10n.settingsAutoCheckUpdatesDescription,
        value: enabled,
        onChanged: (value) {
          unawaited(
            ref
                .read(appSettingsProvider.notifier)
                .setAutoCheckForUpdates(enabled: value),
          );
        },
      ),
    );
  }
}

/// Settings → General toggle for rehydrating the persisted workspace at
/// launch.
///
/// The preference existed on [CoreSettings] and was persisted from the day the
/// workspace landed, but no product in the suite surfaced it, so the only way
/// to turn it off was `defaults write`. The subtitle names the consequence a
/// user actually cares about — the saved session is kept, not discarded — so
/// turning the toggle off does not read as "lose my tabs".
class _RestoreTabsOnLaunchTile extends ConsumerWidget {
  const _RestoreTabsOnLaunchTile({required this.enabled});

  /// Widget key of the toggle, so tests can drive it locale-independently.
  static const Key switchKey = Key('settingsRestoreTabsOnLaunchSwitch');

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    // The form row's label is a plain string, so the help icon rides beside
    // the row (the same placement the Yosys path tile uses for its control).
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: CruxFormRow.toggle(
              key: switchKey,
              label: l10n.settingsRestoreTabsOnLaunchLabel,
              help: l10n.settingsRestoreTabsOnLaunchDescription,
              value: enabled,
              onChanged: (value) {
                unawaited(
                  ref
                      .read(appSettingsProvider.notifier)
                      .setRestoreTabsOnLaunch(enabled: value),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          CruxHelpLink(
            url: HelpUrls.filesAndProjects,
            tooltip: l10n.helpLinkLearnMore,
          ),
        ],
      ),
    );
  }
}

/// Release-build gate for the three diagnostics surfaces.
///
/// Shown only in release builds: debug and profile enable the surfaces
/// unconditionally, so a toggle there would be a control that changes
/// nothing — worse than no control at all.
class _DiagnosticsEnabledTile extends ConsumerWidget {
  const _DiagnosticsEnabledTile({required this.enabled});

  /// Widget key of the toggle, so tests can drive it locale-independently.
  static const Key switchKey = Key('settingsDiagnosticsEnabledSwitch');

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: CruxFormRow.toggle(
        key: switchKey,
        label: l10n.diagnosticsSettingsLabel,
        help: l10n.diagnosticsSettingsDescription,
        value: enabled,
        onChanged: (value) {
          unawaited(
            ref
                .read(appSettingsProvider.notifier)
                .setDiagnosticsEnabled(enabled: value),
          );
        },
      ),
    );
  }
}

/// The "Learn more" link for the CXP section, a row of its own under the shared
/// section (which carries no link of its own).
class _CxpHelpRow extends StatelessWidget {
  const _CxpHelpRow();

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: CruxHelpLink(
          url: HelpUrls.integrations,
          tooltip: l10n.helpLinkLearnMore,
        ),
      ),
    );
  }
}
