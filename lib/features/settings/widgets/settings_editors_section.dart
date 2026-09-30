// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Settings → Editors.
///
/// Dedicated section for external-editor integration: every Crux app
/// exposes an "Editors"
/// settings section, because editor configuration is cross-feature rather
/// than CXP-specific. NetCrux's only editor setting today is the command
/// template run for inbound CXP `request_open_source` messages
/// (`AppSettings.cxpEditorCommand`, with `{file}` / `{line}` / `{column}`
/// tokens) — it previously lived inside the CXP Cross-Probe section and
/// moved here unchanged (same persisted key, same notifier), mirroring
/// WaveCrux's `SettingsEditorsSection`. If NetCrux later grows
/// LintCrux-style preset / args-template editor config (LintCrux's
/// `settings_editors_section.dart` is the reference shape), it belongs in
/// this section.
class SettingsEditorsSection extends ConsumerStatefulWidget {
  /// Creates the Editors settings section showing [currentCommand].
  const SettingsEditorsSection({required this.currentCommand, super.key});

  /// The persisted editor command template at build time.
  final String currentCommand;

  @override
  ConsumerState<SettingsEditorsSection> createState() =>
      _SettingsEditorsSectionState();
}

class _SettingsEditorsSectionState
    extends ConsumerState<SettingsEditorsSection> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentCommand);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return CruxSettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: l10n.settingsCxpEditorCommandLabel,
              // The default template, not a translated string: its tokens
              // are the ones EditorOpenService substitutes, and a hint a
              // user copies into the field has to work.
              hintText: AppSettings.defaultCxpEditorCommand,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              unawaited(
                ref
                    .read(appSettingsProvider.notifier)
                    .setCxpEditorCommand(value),
              );
            },
          ),
        ),
      ],
    );
  }
}
