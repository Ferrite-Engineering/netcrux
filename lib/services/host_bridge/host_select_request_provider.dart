// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart';

/// A cell or net the host asked this build to select.
typedef HostSelectRequest = ({int sequence, HostBridgeSelect select});

/// The latest `select` request, or null once the workspace has taken it.
///
/// Each request carries a sequence number, so the same name asked for twice
/// still notifies the listener and is answered twice.
final hostSelectRequestProvider =
    NotifierProvider<HostSelectRequestNotifier, HostSelectRequest?>(
      HostSelectRequestNotifier.new,
      name: 'hostSelectRequestProvider',
    );

/// Holds the pending [HostSelectRequest].
class HostSelectRequestNotifier extends Notifier<HostSelectRequest?> {
  int _sequence = 0;

  @override
  HostSelectRequest? build() => null;

  /// Queues [select] for the workspace.
  void submit(HostBridgeSelect select) {
    _sequence += 1;
    state = (sequence: _sequence, select: select);
  }

  /// Drops the pending request.
  void clear() => state = null;
}
