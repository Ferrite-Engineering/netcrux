// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/crux_eula.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/app.dart';

/// The root-scope overrides a widget test needs to boot `NetcruxApp`.
///
/// [netcruxAppOverrides] alone is the *production* wiring; a widget test needs
/// two things on top of it, and [kEulaAcceptedPrefs] besides:
///
/// 1. **No live update check.** `updateCheckServiceProvider` resolves to the
///    live HTTP service once build info loads. Pinning the no-op keeps the
///    suite off the network even if a test does mock `PackageInfo`.
/// 2. **No 24-hour periodic timer.** `UpdateStatusNotifier.build` starts one,
///    and `flutter_test` asserts no timer outlives the widget tree. The
///    production notifier cancels it in `ref.onDispose`, but a test that
///    disposes its root `ProviderContainer` from `addTearDown` runs that
///    *after* the pending-timer check — so the assert fires on a perfectly
///    correct app. [NoTimerUpdateStatusNotifier] keeps `checkNow` /
///    `runScheduledCheck` real while omitting the timer.
///
/// Spread this instead of [netcruxAppOverrides] in any test that mounts the
/// root widget.
List<Override> netcruxAppTestOverrides() => <Override>[
  ...netcruxAppOverrides,
  updateCheckServiceProvider.overrideWithValue(const NoopUpdateCheckService()),
  updateStatusProvider.overrideWith(NoTimerUpdateStatusNotifier.new),
];

/// Mock `SharedPreferences` contents that say "this installation has already
/// accepted the current EULA".
///
/// Merge this into `SharedPreferences.setMockInitialValues` in any test that
/// mounts the root widget. Without it `CruxEulaGate` mounts a blocking modal
/// over everything — exactly right in production, and wrong for a test of
/// anything else: a focus walk would report the agreement instead of the start
/// screen, and every root-widget test would be measuring the dialog.
///
/// Seeded through the preference rather than by overriding
/// `cruxEulaStorageProvider`, because the production override list already
/// binds that provider and Riverpod rejects a second override in the same
/// container. This also exercises the real adapter, so a broken
/// `NetcruxEulaStorage` still shows up.
///
/// Seeding acceptance is honest here because the gate is not what these tests
/// are about — the agreement has its own tests in `crux_eula`, and
/// `test/static/eula_gate_reachability_test.dart` is what stops this seed
/// quietly hiding an un-mounted gate.
const Map<String, Object> kEulaAcceptedPrefs = <String, Object>{
  kCruxEulaAcceptedVersionKey: kCruxEulaVersion,
};

/// [UpdateStatusNotifier] without the periodic-check timer. See
/// [netcruxAppTestOverrides].
class NoTimerUpdateStatusNotifier extends UpdateStatusNotifier {
  @override
  UpdateStatus build() => const UpdateStatusCurrent();
}
