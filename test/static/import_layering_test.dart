// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Layering guard — enforces the dependency-flow ruling documented in
/// `docs/ARCHITECTURE.md` §6.2.
///
/// The layer matrix (source layer → layers it may import):
///
/// - `domain/`   → domain only. Hermetic: additionally must not import
///                 Flutter or Riverpod packages at all.
/// - `services/` → domain, services, l10n — never features, EXCEPT the
///                 composition allowlist below (wiring modules whose job
///                 is binding feature state across boundaries).
/// - `core/`     → core, l10n (SDK + localized labels only).
/// - `shared/`   → shared, core, domain, l10n.
/// - `plugins/`  → plugins, domain.
/// - `features/` → anything, EXCEPT another feature's `widgets/` or
///                 `screens/` — mounting another feature's UI is the
///                 workspace shell's job. (Providers/models/services of
///                 sibling features are fair game; that is how Riverpod
///                 state composes.)
/// - Files directly under `lib/` (app.dart, main.dart, app_router.dart,
///   netcrux_color_theme_bootstrap.dart) are the composition root and
///   are exempt as sources; no layer may import them back.
///
/// Escape hatches, in preference order: (1) the type you need is pure —
/// move it into `domain/models/`; (2) the file's *purpose* is wiring —
/// add it to the composition allowlist below with a one-line
/// justification. Do not widen the matrix itself without amending
/// ARCHITECTURE.md §6.2.
void main() {
  /// services/ files whose job is composition: binding per-tab feature
  /// notifiers into scopes, bridging feature state to the wire, or
  /// reacting to feature-owned settings/project state. These may import
  /// `features/`; nothing else in services/ may.
  const compositionAllowlist = <String>{
    // Per-tab ProviderScope override list — exists to bind feature
    // notifiers (selection, viewport, trace overlay, project, …) into
    // each tab's scope.
    'lib/services/workspace/netcrux_tab_overrides.dart',
    // Per-pane ProviderScope override list — same role, pane scope.
    'lib/services/workspace/netcrux_pane_overrides.dart',
    // Session save/restore sweeps every per-tab feature notifier by
    // design; that reach is its function, not layering rot.
    'lib/services/session/session_controller.dart',
    // CXP bridge, outbound: watches feature selection state and emits
    // it over the wire.
    'lib/services/remote/cxp/cxp_outbound_emitter_controller.dart',
    // CXP bridge, inbound: applies wire messages to feature state.
    'lib/services/remote/cxp/cxp_inbound_handler.dart',
    // Auto-reload wiring: reacts to the current project + settings
    // providers to re-elaborate on source change.
    'lib/services/reload/source_file_watcher_provider.dart',
    // Reads the user-configured Yosys path from appSettingsProvider
    // (settings state is owned by the settings feature per
    // `docs/ARCHITECTURE.md` §6.1).
    'lib/services/yosys/yosys_executable_provider.dart',
    // CXP path containment: its roots include the recent-files lists, which
    // appSettingsProvider (the settings feature) owns. Without them a peer
    // cannot reopen a design whose tab was closed.
    'lib/services/remote/cxp/cxp_workspace_link.dart',
    // Launch gate: reads the persisted `restoreTabsOnLaunch` preference
    // through settingsServiceProvider before the workspace document is
    // loaded. Same standing as the Yosys path reader — settings state is
    // owned by the settings feature, and the gate has to run inside
    // WorkspaceNotifier.build because that is the only caller of
    // WorkspaceService.load.
    'lib/services/workspace/netcrux_workspace_notifier.dart',
  };

  /// Lateral widget/screen imports allowed from non-workspace features.
  /// Key = importing file, value = the one target it may import.
  ///
  /// Empty by design. The lateral rule has no standing exception: the
  /// only two entries it ever carried both reached
  /// `WorkspaceManagersScope`, which is container-manager plumbing rather
  /// than workspace UI and now lives in `shared/widgets/`. A file that
  /// wants a sibling feature's widget is either reaching for something
  /// that belongs in `shared/` or reaching past the shell.
  const lateralWidgetAllowlist = <String, String>{};

  /// Frameworks domain/ must never touch (hermetic layer).
  final domainForbiddenPackages = RegExp(
    '^package:(flutter|flutter_riverpod|riverpod|riverpod_annotation|'
    "hooks_riverpod|go_router)[/']",
  );

  /// Matrix of netcrux-internal layers each layer may import from.
  const allowedTargets = <String, Set<String>>{
    'domain': {'domain'},
    'services': {'domain', 'services', 'l10n'},
    'core': {'core', 'l10n'},
    'shared': {'shared', 'core', 'domain', 'l10n'},
    'plugins': {'plugins', 'domain'},
    // features handled separately (lateral widget/screen rule).
  };

  final directive = RegExp(r"^(?:import|export)\s+'([^']+)'");
  final violations = <String>[];

  void checkFile(File file) {
    final path = file.path.replaceAll(r'\', '/');
    final rel = path.substring(path.indexOf('lib/'));
    final segments = rel.split('/');
    // Files directly under lib/ are the composition root — exempt.
    if (segments.length == 2) return;
    final layer = segments[1];
    final sourceFeature = layer == 'features' ? segments[2] : null;

    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final match = directive.firstMatch(lines[i]);
      if (match == null) continue;
      final target = match.group(1)!;
      final where = '$rel:${i + 1}';

      if (layer == 'domain' && domainForbiddenPackages.hasMatch("$target'")) {
        violations.add(
          '$where imports $target — domain/ is hermetic (no Flutter, no '
          'Riverpod). Push the framework-facing half up into features/ or '
          'services/.',
        );
        continue;
      }

      if (!target.startsWith('package:netcrux/')) continue;
      final targetSegments = target
          .substring('package:netcrux/'.length)
          .split(
            '/',
          );
      final targetLayer = targetSegments.length == 1
          ? 'root'
          : targetSegments[0];

      if (targetLayer == 'root') {
        violations.add(
          '$where imports $target — composition-root files (directly under '
          'lib/) must not be imported from layers; only app.dart/main.dart '
          'wire them.',
        );
        continue;
      }

      if (layer == 'features') {
        // Lateral rule: another feature's widgets/ or screens/ may only
        // be mounted by the workspace shell.
        if (targetLayer == 'features' &&
            targetSegments.length >= 3 &&
            (targetSegments[2] == 'widgets' ||
                targetSegments[2] == 'screens') &&
            targetSegments[1] != sourceFeature &&
            sourceFeature != 'workspace' &&
            lateralWidgetAllowlist[rel] != target) {
          violations.add(
            '$where imports $target — lateral widget/screen imports are '
            'reserved for the workspace shell. Depend on the sibling '
            "feature's providers/models instead, or (for genuine shell "
            'wiring) add an entry to lateralWidgetAllowlist with a '
            'justification.',
          );
        }
        continue;
      }

      final allowed = allowedTargets[layer];
      if (allowed == null) continue; // unknown top-level dir; l10n etc.
      if (allowed.contains(targetLayer)) continue;
      if (layer == 'services' &&
          targetLayer == 'features' &&
          compositionAllowlist.contains(rel)) {
        continue;
      }
      violations.add(
        '$where imports $target — $layer/ may only import '
        '{${allowed.join(', ')}}. If the needed type is pure, move it to '
        "domain/models/; if this file's purpose is wiring, add it to the "
        'compositionAllowlist with a justification.',
      );
    }
  }

  test('lib/ obeys the ARCHITECTURE.md §6.2 layer matrix', () {
    final files =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.endsWith('.g.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty, reason: 'lib/ must exist and contain Dart files');
    files.forEach(checkFile);

    expect(
      violations,
      isEmpty,
      reason:
          'Layering violations (see docs/ARCHITECTURE.md §6.2 for the '
          'ruling):\n${violations.join('\n')}',
    );
  });

  test('the lateral widget/screen allowlist stays empty', () {
    expect(
      lateralWidgetAllowlist,
      isEmpty,
      reason:
          'The lateral rule has no standing exception. A widget two '
          'features need is shared/ infrastructure — move it there rather '
          'than blessing the import.',
    );
  });

  test('composition allowlist entries still exist and still need blessing', () {
    for (final entry in compositionAllowlist) {
      final file = File(entry);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            '$entry is on the composition allowlist but no longer exists — '
            'remove the stale entry.',
      );
      final imports = file.readAsLinesSync().where(
        (l) => l.contains("import 'package:netcrux/features/"),
      );
      expect(
        imports,
        isNotEmpty,
        reason:
            '$entry no longer imports features/ — it has earned its way off '
            'the composition allowlist; remove the entry.',
      );
    }
  });
}
