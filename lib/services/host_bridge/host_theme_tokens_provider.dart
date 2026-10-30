// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart';

/// The editor's latest resolved colors, or null until the host has sent them.
///
/// The bridge only records what the host sent. Turning the tokens into a theme
/// and applying it is the composition root's job (`bootstrap`), because it
/// reaches the color-theme notifier, which no layer may import.
final hostThemeTokensProvider =
    NotifierProvider<HostThemeTokensNotifier, HostBridgeThemeTokens?>(
      HostThemeTokensNotifier.new,
      name: 'hostThemeTokensProvider',
    );

/// Holds the latest [HostBridgeThemeTokens].
class HostThemeTokensNotifier extends Notifier<HostBridgeThemeTokens?> {
  @override
  HostBridgeThemeTokens? build() => null;

  /// Records [tokens], replacing the previous ones.
  // ignore: use_setters_to_change_properties
  void submit(HostBridgeThemeTokens tokens) {
    state = tokens;
  }
}
