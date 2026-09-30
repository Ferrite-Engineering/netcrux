// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:netcrux/features/settings/screens/settings_screen.dart';
import 'package:netcrux/features/workspace/screens/workspace_screen.dart';

/// The root navigator's key.
///
/// The desktop menu bar mounts above the router (see
/// `NetcruxApp._buildAppChrome`), so when nothing holds focus it needs a
/// context inside the routed tree to dispatch a `NetcruxActionIntent` from.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Root [ScaffoldMessengerState] key. Held outside the widget tree so
/// app-lifecycle callbacks (workspace hydration, missing-file recovery) can
/// surface snackbars without owning a [BuildContext]. Wired into
/// [MaterialApp.router]'s `scaffoldMessengerKey`.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'netcrux_root_messenger');

/// Application route table.
///
/// Routes:
/// - `/` — [`WorkspaceScreen`]. Hosts the IdeLayout chrome plus the
///   workspace-aware [`PaneHost`] in the center pane. Renders the
///   empty-canvas state when `workspace.tabs.isEmpty`. There is no separate
///   Welcome route; the empty canvas is the start screen.
/// - `/settings` — Settings screen.
///
/// The legacy `/project/:projectId` route is retired — the workspace
/// model addresses tabs by [`TabId`], not by an opaque project id.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) => webDeepLinkRedirect(state.uri),
    routes: [
      GoRoute(
        path: '/',
        name: 'workspace',
        builder: (context, state) => const WorkspaceScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  ),
);

/// Sends the web viewer's deep-link fragment home instead of to a route.
///
/// The browser build routes through the URL fragment, so a shared link's
/// `#scope=top.cpu&sig=alu_y` reaches the router as the location
/// `/scope=top.cpu&sig=alu_y` and would land on "page not found". `bootstrap`
/// has already read those hints out of `window.location` before the router
/// exists, so the router only has to show the workspace. A location is a
/// hint, never a route, when its single segment is a `key=value` pair — no
/// route path contains `=`.
@visibleForTesting
String? webDeepLinkRedirect(Uri location) {
  final segments = location.pathSegments;
  if (segments.length == 1 && segments.single.contains('=')) return '/';
  return null;
}
