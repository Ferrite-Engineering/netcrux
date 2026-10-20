// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The request handler a mounted workspace publishes for the shared CXP
/// runtime, or null while none is mounted.
///
/// NetCrux's handler acts on the active tab's container, which only a widget
/// under the workspace can reach (`WorkspaceManagersScope`), so it cannot be
/// built by a root provider. The workspace builds it and publishes it here;
/// `cruxCxpRequestHandlerProvider` is overridden to read this, and the runtime
/// reads the handler again at each request, so publishing needs no restart.
final NotifierProvider<CxpInboundHandlerHolder, CruxCxpRequestHandler?>
netcruxInboundHandlerHolderProvider =
    NotifierProvider<CxpInboundHandlerHolder, CruxCxpRequestHandler?>(
      CxpInboundHandlerHolder.new,
      name: 'netcruxInboundHandlerHolderProvider',
    );

/// Backs [netcruxInboundHandlerHolderProvider].
class CxpInboundHandlerHolder extends Notifier<CruxCxpRequestHandler?> {
  @override
  CruxCxpRequestHandler? build() => null;

  /// The published handler, or null.
  CruxCxpRequestHandler? get handler => state;

  /// Publishes the handler the runtime asks.
  set handler(CruxCxpRequestHandler? handler) => state = handler;

  /// Withdraws [handler], when it is still the published one; a handler
  /// already replaced by a newer mount stays.
  void withdraw(CruxCxpRequestHandler handler) {
    if (identical(state, handler)) state = null;
  }
}
