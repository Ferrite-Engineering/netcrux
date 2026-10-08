// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the dialog that starts hosting a collaborative session.
///
/// The dispatcher has already applied the tier gate (hosting is the
/// Enterprise step) by the time this runs, so the opener only opens.
typedef ShareSessionOpener = void Function(BuildContext context);

/// Opens the dialog that joins a collaborative session somebody else hosts.
///
/// Joining is free in every edition; nothing gates this.
typedef JoinSessionOpener = void Function(BuildContext context);

/// Open-core extension point for File > Share Session….
///
/// Default is a no-op, so the action stays discoverable (and badged) in an
/// open-core build, where the dispatcher's Pro-action gate refuses it with a
/// "requires NetCrux Pro" notice before this is reached. The collaboration
/// overlay overrides it with a callback that opens its Share dialog.
final shareSessionOpenerProvider = Provider<ShareSessionOpener>(
  (_) => (_) {
    // Open-core no-op. The collaboration overlay overrides this.
  },
  name: 'shareSessionOpenerProvider',
);

/// Open-core extension point for File > Join Session….
///
/// Default is a no-op; in an open-core build the action is not offered at all
/// (`collaborationAvailableProvider` is false). The collaboration overlay
/// overrides it with a callback that opens its Join dialog.
final joinSessionOpenerProvider = Provider<JoinSessionOpener>(
  (_) => (_) {
    // Open-core no-op. The collaboration overlay overrides this.
  },
  name: 'joinSessionOpenerProvider',
);
