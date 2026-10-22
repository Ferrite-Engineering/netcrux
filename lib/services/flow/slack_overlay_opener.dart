// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows or hides the slack overlay's panel in the active tab.
///
/// The overlay is a NetCrux Pro capability, so open core resolves
/// [toggleSlackOverlayOpenerProvider] to null and the action that reaches it
/// answers with the "requires NetCrux Pro" notice instead of doing nothing.
typedef ToggleSlackOverlayOpener = void Function(BuildContext context);

/// The overlay's [ToggleSlackOverlayOpener]; null in open core.
final Provider<ToggleSlackOverlayOpener?> toggleSlackOverlayOpenerProvider =
    Provider<ToggleSlackOverlayOpener?>(
      (_) => null,
      name: 'toggleSlackOverlayOpenerProvider',
    );
