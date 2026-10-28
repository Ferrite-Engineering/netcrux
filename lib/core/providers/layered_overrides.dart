// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `Override.origin` names the provider an override replaces, and is the only
// way to tell which provider that is. Riverpod marks it visible for testing;
// it is read here, and only here, so that an overlay can replace an open-core
// binding at all. A rename in Riverpod fails this file's build, not silently.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_riverpod/misc.dart' show Override;

/// [base] with every entry dropped that overrides a provider [top] also
/// overrides, followed by all of [top].
///
/// This is how an overlay's overrides replace the open core's: the overlay's
/// entry wins, and the container never sees one provider overridden twice,
/// which Riverpod refuses with "Tried to override a provider twice within the
/// same container" in a debug build (a release build keeps the last one
/// silently). Without it, any open-core seam the core itself binds could not
/// be rebound by the overlay without breaking every debug and integration
/// launch.
List<Override> layeredOverrides(List<Override> base, List<Override> top) {
  final replaced = <Object?>{for (final o in top) o.origin};
  return <Override>[
    for (final o in base)
      if (!replaced.contains(o.origin)) o,
    ...top,
  ];
}
