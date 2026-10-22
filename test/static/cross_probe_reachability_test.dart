// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The shared CXP and Recent-list surfaces are only worth anything if the app
// calls them. A green suite with a handler nothing installs, a menu entry
// nothing builds or a Clear Recent nothing runs is the shipped-but-unreachable
// defect class, so this pins the call sites by reading `lib/`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _libSources() {
  final sources = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (!path.endsWith('.dart') || path.endsWith('.g.dart')) continue;
    if (path.contains('/l10n/generated/')) continue;
    sources[path] = entity.readAsStringSync();
  }
  return sources;
}

/// The files under `lib/` whose source contains [needle].
List<String> _callers(Map<String, String> sources, String needle) => [
  for (final entry in sources.entries)
    if (entry.value.contains(needle)) entry.key,
];

void main() {
  final sources = _libSources();

  test('the shared surfaces are called from the app', () {
    const surfaces = <String, String>{
      // The menu entry, the command and Clear Recent: the three the contract
      // names, each reachable from a menu, the palette or a shortcut.
      'crossProbeMenuEntry(': 'lib/features/viewer/widgets/',
      'runCrossProbeSelection(': 'lib/features/workspace/services/',
      'clearCruxRecentList(': 'lib/features/workspace/services/',
      'CruxRecentListSection(': 'lib/features/workspace/widgets/',
      'CruxCrossProbePanel(': 'lib/features/remote/widgets/',
      'CruxCxpSettingsSection(': 'lib/features/settings/screens/',
      'broadcastCruxCxpSelection(': 'lib/services/remote/cxp/',
      'CxpInboundHandlerPublisher(': 'lib/features/workspace/screens/',
    };
    for (final entry in surfaces.entries) {
      final callers = _callers(sources, entry.key);
      expect(
        callers.where((path) => path.startsWith(entry.value)),
        isNotEmpty,
        reason:
            '${entry.key} is not called from ${entry.value}: the surface '
            'exists and nothing reaches it. Callers: $callers',
      );
    }
  });

  test('the Formal and Flow receivers are reached from the app', () {
    const reached = <String, String>{
      // The handler asks the overlay's seams; open core answers without one.
      'rootContainer.read(inboundPropertyConeProvider)':
          'lib/services/remote/cxp/cxp_inbound_handler.dart',
      'rootContainer.read(flowArtifactOpenerProvider)':
          'lib/services/remote/cxp/cxp_inbound_handler.dart',
      // A received path is written per tab and shown by the Inspector.
      'receivedTimingPathProvider.notifier).show(':
          'lib/services/remote/cxp/cxp_inbound_handler.dart',
      'receivedTimingPathProvider.overrideWith(':
          'lib/services/workspace/netcrux_tab_overrides.dart',
      'TimingPathInspectorSection()':
          'lib/features/inspector/widgets/inspector_panel.dart',
      // The originate entry sits beside "Cross-probe to".
      'netcruxRegisterSignalSelectionOf(':
          'lib/features/viewer/widgets/cross_probe_menu_entries.dart',
      // The active design is announced for as long as the workspace is up,
      // and toasts about peer-started requests reach the user.
      'cxpActiveDocumentSyncProvider':
          'lib/features/remote/widgets/cxp_inbound_handler_publisher.dart',
      'notice: _notice':
          'lib/features/remote/widgets/cxp_inbound_handler_publisher.dart',
    };
    for (final entry in reached.entries) {
      expect(
        sources[entry.value],
        contains(entry.key),
        reason: '${entry.key} is not reached from ${entry.value}',
      );
    }
  });

  test("the request handler is installed from the app's root overrides", () {
    final overrides = sources['lib/features/remote/netcrux_cxp_overrides.dart'];
    expect(overrides, isNotNull);
    expect(
      overrides,
      contains('cruxCxpRequestHandlerProvider.overrideWith('),
      reason:
          'without it the runtime acknowledges every request as '
          'unsupported',
    );
    expect(
      overrides,
      contains('netcruxInboundHandlerHolderProvider'),
      reason: 'the override must read the handler the workspace publishes',
    );
    final app = sources['lib/app.dart']!;
    expect(
      app,
      contains('...netcruxCxpOverrides'),
      reason:
          'the CXP overrides must be part of the root overrides every '
          'host installs',
    );
    expect(
      app,
      contains('loadCruxCxpLaunchSettings('),
      reason: 'bootstrap loads the saved CXP settings before runApp',
    );
  });

  test('every open records itself in a Recent list', () {
    final screen =
        sources['lib/features/workspace/screens/workspace_screen.dart']!;
    for (final list in const <String>[
      'recentProjects',
      'recentSources',
      'recentWorkspaces',
    ]) {
      expect(
        screen,
        contains('$list.provider.notifier).markOpened'),
        reason: 'no open records itself in $list',
      );
    }
    expect(
      sources['lib/features/workspace/services/workspace_action_dispatcher.dart'],
      contains('recent.markOpened(saved)'),
      reason: 'Save Project As… adds its file to Recent Projects',
    );
  });

  test('the product no longer owns the CXP lifecycle or the CXP settings', () {
    // These were deleted in favour of the shared lifecycle; a copy coming back
    // would double-write the keys and double-acknowledge requests.
    for (final removed in const <String>[
      'cxpServerHostProvider',
      'NetcruxCxpServer',
      'cxpServerEnabled',
      'requestAttentionOnCrossProbe:',
      'broadcastSelectionOnCrossProbe:',
    ]) {
      final callers = _callers(sources, removed).where(
        (path) =>
            // The codec documents the four keys it no longer writes.
            path != 'lib/services/settings/netcrux_settings_codec.dart',
      );
      expect(
        callers,
        isEmpty,
        reason:
            '$removed is the lifecycle copy that was removed; the shared '
            'one is the only one. Found in: $callers',
      );
    }
  });
}
