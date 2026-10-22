// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;

/// The design this window shows, as peers are told it (CXP §8.1
/// `active_document`): the active tab's name, or null when no tab is
/// active or the active tab has no design in it.
///
/// A name, never a directory: a tab named after a path is cut to its last
/// segment. Peers show it beside this window in their "Cross-probe to"
/// menus, so two NetCrux windows can be told apart.
final Provider<String?> cxpActiveDocumentProvider = Provider<String?>((ref) {
  final workspace = ref.watch(netcruxWorkspaceProvider).value;
  if (workspace == null) return null;
  final activeId = workspace.activeTabId;
  if (activeId == null) return null;
  for (final tab in workspace.tabs) {
    if (tab.id != activeId) continue;
    if (tab.payload.sourceFiles.isEmpty &&
        tab.payload.projectFilePath == null) {
      return null;
    }
    final name = p.basename(tab.displayName.replaceAll(r'\', '/'));
    return name.isEmpty ? null : name;
  }
  return null;
}, name: 'cxpActiveDocumentProvider');

/// Keeps the running CXP runtime's announced design in step with
/// [cxpActiveDocumentProvider]: switching tabs, opening a design into a tab
/// and closing the last tab each rewrite this window's manifest. Watched by
/// the workspace's request-handler publisher, so it lives exactly as long as
/// the workspace does.
final Provider<void> cxpActiveDocumentSyncProvider = Provider<void>((ref) {
  final document = ref.watch(cxpActiveDocumentProvider);
  final runtime = ref.watch(cruxCxpRuntimeProvider).value;
  if (runtime == null) return;
  unawaited(runtime.setActiveDocument(document));
}, name: 'cxpActiveDocumentSyncProvider');
