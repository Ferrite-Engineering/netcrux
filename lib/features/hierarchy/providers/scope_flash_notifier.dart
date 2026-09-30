// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'scope_flash_notifier.g.dart';

/// A one-shot "flash this scope" request — the hierarchy tree pulses the
/// matching row's background briefly so an inbound navigation produces a
/// visible cue even when it lands on the scope the user is ALREADY viewing.
///
/// Carries the target scope's expansion key ([pathKey] — a
/// `HierarchyNode.path` joined by `/`, the same key
/// [HierarchyTreeState.expandedKeys] uses) plus a monotonically increasing
/// [nonce]. The nonce is what makes a repeat flash of the SAME scope
/// re-trigger the animation: two `ScopeFlashRequest`s for the same node still
/// compare unequal, so the row's `didUpdateWidget` fires again.
///
/// This is the scope analogue of [RevealRequestNotifier] (which centres the
/// viewport on a cell): a cross-probe that resolves to a scope has no single
/// cell to reveal, and selecting the scope is a no-op when it is already
/// selected — so without this flash a "show this module" cross-probe onto the
/// current/top scope changed nothing on screen.
@immutable
class ScopeFlashRequest {
  /// Creates a flash request for the scope at [pathKey] with sequence [nonce].
  const ScopeFlashRequest({required this.pathKey, required this.nonce});

  /// The target scope's expansion key — `HierarchyNode.path.join('/')`. The
  /// empty string is the top/root scope.
  final String pathKey;

  /// Monotonic sequence so repeated flashes of the same [pathKey] still
  /// notify (each `flash` increments it).
  final int nonce;

  @override
  bool operator ==(Object other) =>
      other is ScopeFlashRequest &&
      other.pathKey == pathKey &&
      other.nonce == nonce;

  @override
  int get hashCode => Object.hash(pathKey, nonce);
}

/// Holds the pending scope-flash request for one tab. Written by the CXP
/// inbound handler when an inbound scope highlight resolves (see
/// `CxpInboundHandler`), read by the hierarchy tree so the resolved row
/// pulses.
///
/// Scoped per-tab (see [`netcruxTabOverridesFactory`]) alongside
/// [`hierarchyTreeProvider`] and [`revealRequestProvider`] so a flash acts on
/// the focused tab's tree.
@Riverpod(keepAlive: true)
class ScopeFlashNotifier extends _$ScopeFlashNotifier {
  @override
  ScopeFlashRequest? build() => null;

  /// Requests a flash of the scope whose [path] is the instance-name path from
  /// the top module (empty for the top scope). Always bumps the nonce so a
  /// flash of the same scope re-triggers.
  void flash(List<String> path) {
    final key = path.join('/');
    state = ScopeFlashRequest(pathKey: key, nonce: (state?.nonce ?? 0) + 1);
  }

  /// Clears a satisfied flash request.
  void clear() {
    if (state == null) return;
    state = null;
  }
}
