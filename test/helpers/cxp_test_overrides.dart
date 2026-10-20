// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';

/// The shared CXP lifecycle as NetCrux binds it, and never started, for a test
/// that builds its own root container and mounts something that reads the CXP
/// providers (the cross-probe panel, the toolbar badge, the schematic menu, a
/// design opening). With no transport there is no runtime, so no socket is
/// bound and no discovery manifest is written; the peer list is empty and the
/// server reads as off.
///
/// A test that needs peers or a running server overrides the providers it
/// cares about after these (`cruxCxpPeersProvider`, `cruxCxpServerStatusProvider`,
/// `cruxCxpRuntimeProvider`).
List<Override> netcruxCxpOffTestOverrides() => <Override>[
  cruxCxpProductBindingProvider.overrideWithValue(kNetcruxCxpBinding),
  cruxCxpTransportAvailableProvider.overrideWithValue(false),
  // No discovery stream: a stream provider resolving mid-test schedules a
  // refresh timer a fake-async test would end with.
  cruxCxpPeersProvider.overrideWithValue(const []),
  cruxCxpServerStatusProvider.overrideWithValue((
    running: false,
    port: 0,
    problem: null,
  )),
];
