// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/core/telemetry/netcrux_telemetry_config.dart';

/// Telemetry wiring for a test that builds its own container and is about
/// something other than telemetry.
///
/// During the public beta the telemetry gate was closed before anything read
/// the product's configuration, so a container with no telemetry wiring
/// never noticed. With the beta over the gate is live: any feature that
/// records an event — a cross-probe, a search, a workspace change — reaches
/// `cruxTelemetryConfigProvider`, whose package default throws, and then the
/// consent store, which settles asynchronously and leaves a provider refresh
/// in flight when a short test ends.
///
/// So this binds the configuration `bootstrap` binds, and closes the gate
/// the way an organization's policy file closes it: synchronously, before
/// the consent store is consulted. Nothing is sent, nothing waits, and the
/// feature under test records exactly as it does in production. A test
/// about telemetry itself binds what it needs directly instead.
List<Override> netcruxTelemetryTestOverrides() => <Override>[
  cruxTelemetryConfigProvider.overrideWithValue(netcruxTelemetryConfig),
  telemetryPolicyProvider.overrideWithValue(TelemetryPolicy.deny),
];
