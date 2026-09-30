// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether an X-trace back-cone walk is currently running.
///
/// `XTraceService.traceAsync` is genuinely asynchronous: the Pro walker
/// offloads to a background isolate once the scope exceeds its cell threshold,
/// so a large design produces a visible gap between the action firing and the
/// chain appearing. The panel renders a determinate-free progress line in
/// place of its divider while this is true, keeping the *previous* chain
/// visible underneath rather than blanking to the empty state — a walk in
/// progress is not the same thing as no result.
///
/// Root-scoped and written only by `WorkspaceActionDispatcher` around its
/// single `await`. That is a deliberate simplification over per-tab scoping:
/// the dispatcher runs one walk at a time from the focused tab, so the only
/// way to observe the flag against the wrong tab is to switch tabs mid-walk
/// and see a progress line for the duration of someone else's isolate. If a
/// future revision dispatches concurrent walks per tab, this becomes a per-tab
/// override alongside `xTraceResultProvider`.
class XTraceInFlightNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Marks a walk as started or finished.
  // ignore: use_setters_to_change_properties
  void set({required bool running}) => state = running;
}

/// Whether an X-trace walk is in flight. See [XTraceInFlightNotifier].
final xTraceInFlightProvider = NotifierProvider<XTraceInFlightNotifier, bool>(
  XTraceInFlightNotifier.new,
  name: 'xTraceInFlightProvider',
);
