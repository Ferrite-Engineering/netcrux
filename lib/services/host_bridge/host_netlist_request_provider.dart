// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart';

/// A netlist the host asked this build to open.
typedef HostNetlistRequest = ({int sequence, HostBridgeOpenNetlist netlist});

/// The latest `open_netlist` request, or null once the workspace has taken it.
///
/// Each request carries a sequence number, so two requests for identical text
/// (a file reloaded unchanged) still notify the listener. The text can be tens
/// of megabytes, so the consumer clears it as soon as it has made the document.
final hostNetlistRequestProvider =
    NotifierProvider<HostNetlistRequestNotifier, HostNetlistRequest?>(
      HostNetlistRequestNotifier.new,
      name: 'hostNetlistRequestProvider',
    );

/// Holds the pending [HostNetlistRequest].
class HostNetlistRequestNotifier extends Notifier<HostNetlistRequest?> {
  int _sequence = 0;

  @override
  HostNetlistRequest? build() => null;

  /// Queues [netlist] for the workspace.
  void submit(HostBridgeOpenNetlist netlist) {
    _sequence += 1;
    state = (sequence: _sequence, netlist: netlist);
  }

  /// Drops the pending request, releasing its text.
  void clear() => state = null;
}
