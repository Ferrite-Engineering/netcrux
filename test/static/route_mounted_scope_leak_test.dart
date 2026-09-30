// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// NetCrux's enablement of the ROUTE-MOUNTED per-tab scope-leak guard.
//
// The rule itself — what it catches, its three accepted forms of re-binding,
// and the seven things it deliberately does NOT catch — lives once in
// crux-shared, next to the scanner it depends on. Read that file first; this
// one only supplies NetCrux's source roots and per-tab seed list.
//
// Why the rule exists, in NetCrux's own terms: a dialog route is a child of
// the Navigator, which sits ABOVE the per-tab `UncontrolledProviderScope`. A
// widget mounted from `showDialog` that reads a per-tab provider through
// `WidgetRef` therefore resolves the ROOT container, where no design is
// loaded. The sibling `per_tab_provider_scope_leak_test` cannot see this: it
// analyses the *provider* graph, and this is a *widget*.
//
// NetCrux is where the bug class was first named. Beta bug N1: the Search
// Design dialog answered "No results." for every query against a fully loaded
// design, and applying a result did nothing, because `SearchDialog` was pushed
// with `showDialog` and its `ref.watch(hierarchyTree…)` resolved the empty
// root container — searching an empty model and writing the selection to a tab
// nobody was looking at. No exception, no log line. It was invisible in a
// single-tab session, and invisible to the existing tests, because every one
// of them used a single `ProviderScope` so the launcher and the dialog shared
// a container.
//
// The allowlist is deliberately empty. A violation is fixed, not listed.

import 'dart:io';

import '../../crux-shared/packages/crux_workspace/test/static/route_mounted_scope_leak_guard.dart';

void main() {
  defineRouteMountedScopeLeakGuard(
    sourceRoots: _sourceRoots,
    // Same seed sources as the sibling provider guard: the open-core per-tab
    // override list, unioned with the Pro overlay's when it is present —
    // `bootstrap` spreads both, so a provider re-bound by either is per-tab in
    // a real tab container.
    seedOverrideSpecs: const [
      'lib/services/workspace/netcrux_tab_overrides.dart',
      '../lib/overrides.dart#proTabOverrides',
    ],
    bootstrapHint: 'run `flutter pub get` in netcrux/',
  );
}

/// Open-core `lib/`, plus the Pro overlay's `lib/` when this checkout is the
/// Pro overlay's submodule — so a taint chain crossing the repo boundary
/// still resolves. A standalone open-core checkout scans open-core only.
List<Directory> _sourceRoots() {
  final roots = <Directory>[Directory('lib')];
  final proLib = Directory('../lib');
  if (proLib.existsSync() && File('../lib/overrides.dart').existsSync()) {
    roots.add(proLib);
  }
  return roots;
}
