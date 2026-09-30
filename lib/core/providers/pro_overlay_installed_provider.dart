// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the NetCrux Pro overlay is installed in this build.
///
/// Open core keeps every Pro-tier action discoverable and badged, with a
/// no-op implementation behind it; the Pro overlay overrides this to `true`
/// alongside the real implementations. The Pro-action gate reads it so a
/// Pro-tier action in an open-core build says it requires NetCrux Pro
/// instead of silently doing nothing — during the beta, when the tier gate
/// itself admits everything, that message is the only feedback there is.
final proOverlayInstalledProvider = Provider<bool>(
  (ref) => false,
  name: 'proOverlayInstalledProvider',
);
