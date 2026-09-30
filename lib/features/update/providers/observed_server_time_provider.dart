// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'observed_server_time_provider.g.dart';

/// Persisted store of the most recently observed authoritative server time —
/// the `server_time` field of the update manifest fetched by `crux_updates`.
///
/// `crux_updates` deliberately does not own the persistence: it emits each
/// observation through `observedServerTimeSinkProvider` and leaves storage to
/// the host, which already has a preferences layer. This store is the NetCrux
/// half of that contract, and its value is fed back into `crux_license`'s
/// `observedServerTimeProvider` so `trustedBetaExpiryNow` reckons beta expiry
/// against the later of the device clock and the last server time seen.
///
/// The value is **monotonic**: [record] only advances it (the later of the
/// stored and the newly observed time), so a stale cached manifest or a server
/// blip can never roll the trusted clock backward. It is persisted to
/// `SharedPreferences` and reloaded on launch, so a later **offline** start
/// still benefits from the last server time the app ever saw.
///
/// `build` returns `null` synchronously and kicks off the async load; once the
/// persisted value arrives the state updates and every watcher (the
/// beta-expiry providers, via the root override) re-evaluates.
@Riverpod(keepAlive: true)
class ObservedServerTimeStore extends _$ObservedServerTimeStore {
  /// SharedPreferences key holding the ISO-8601 server time. Namespaced under
  /// `netcrux.` like every other NetCrux-owned preference so it cannot collide
  /// with another Crux product sharing the same preferences domain.
  static const prefsKey = 'netcrux.update.observedServerTime';

  @override
  DateTime? build() {
    unawaited(_load());
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(prefsKey);
    final parsed = iso == null ? null : DateTime.tryParse(iso);
    if (parsed != null) _advanceTo(parsed);
  }

  /// Records an observed server time, advancing the store (and persisting it)
  /// only when [serverTime] is strictly later than the current value.
  Future<void> record(DateTime serverTime) async {
    if (!_advanceTo(serverTime)) return;
    // Capture the just-advanced value synchronously (still mounted) so the
    // persist path never reads `state` after the getInstance() gap — the
    // store is keepAlive but a container teardown mid-fetch still disposes it.
    final toPersist = state;
    if (toPersist == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, toPersist.toIso8601String());
  }

  /// Sets [state] to [candidate] when it is strictly later than the current
  /// value (or the store is empty). Returns whether the state advanced.
  ///
  /// Both callers reach here after an async gap ([_load] after the prefs read,
  /// [record] from the post-fetch update callback), so a disposed ref must not
  /// touch `state` — bail first.
  bool _advanceTo(DateTime candidate) {
    if (!ref.mounted) return false;
    final current = state;
    if (current != null && !candidate.isAfter(current)) return false;
    state = candidate;
    return true;
  }
}
