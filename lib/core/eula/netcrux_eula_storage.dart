// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/crux_eula.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NetCrux's persistence adapter for the accepted-EULA version.
///
/// Lives in `SharedPreferences` under the suite-fixed key
/// [kCruxEulaAcceptedVersionKey], **outside** the settings document. That is
/// deliberate: settings are the user's preference file, the thing they copy to
/// a second machine or hand to a colleague, and an acceptance must not travel
/// that way. A settings file carried to a new machine must not carry an
/// agreement the person at that machine never accepted.
///
/// Reads and writes **fail soft, towards asking again**, which is the opposite
/// direction from the telemetry adapter beside it. An unreadable telemetry
/// store collects nothing, and that is the safe answer there; an unreadable
/// acceptance store must not be mistaken for an acceptance. EULA section 2.1
/// does not let the application proceed without one, so a broken store
/// presents the agreement rather than skipping it.
class NetcruxEulaStorage extends CruxEulaStorage {
  /// Creates the adapter. Stateless — `SharedPreferences.getInstance()` is
  /// itself cached by the plugin.
  const NetcruxEulaStorage();

  @override
  Future<String?> read(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } on Object catch (_) {
      // Reads as "never accepted", which presents the agreement.
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } on Object catch (_) {
      // The acceptance is lost and the user is asked again next launch. That
      // is an annoyance; treating a failed write as done would leave a build
      // running with no recorded acceptance at all.
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await (await SharedPreferences.getInstance()).remove(key);
    } on Object catch (_) {
      // Same posture as write. `--reset-eula` not taking effect is a testing
      // inconvenience, never a user-facing failure.
    }
  }
}
