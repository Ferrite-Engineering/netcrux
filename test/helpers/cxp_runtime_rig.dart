// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/services/remote/cxp/cxp_inbound_handler.dart';
import 'package:netcrux/services/remote/cxp/editor_open_service.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';

/// The shared CXP runtime NetCrux runs in production, for tests that talk to
/// it over a real loopback socket: NetCrux's own binding (name, accepted
/// kinds, containment), an ephemeral port by default, a test discovery
/// directory, and whichever request handler the test attaches.
///
/// The runtime acknowledges every request and asks for attention itself, so a
/// test that sends a request through a `LocalCxpClient` sees exactly the
/// acknowledgement a peer would.
class CxpRuntimeRig {
  /// Creates a rig whose discovery manifest lives in [manifestDirectory].
  CxpRuntimeRig({
    required String manifestDirectory,
    int port = 0,
    void Function()? onAttention,
    bool Function()? attentionEnabled,
  }) {
    runtime = CruxCxpRuntime(
      binding: kNetcruxCxpBinding,
      productVersion: '0.0.0-test',
      manifestDirectory: manifestDirectory,
      port: port,
      handler: () => handler ?? const CruxCxpRequestHandler(),
      onAttention: onAttention,
      attentionEnabled: attentionEnabled,
      // The server the runtime builds, kept so a test can read its session
      // state. Built exactly as the runtime builds its own.
      serverFactory: (self) => server = LocalCxpServer(
        selfIdentity: self,
        port: port,
        nameResolver: kNetcruxCxpBinding.nameResolver,
        containment: kNetcruxCxpBinding.containment,
      ),
    );
  }

  /// The runtime under test.
  late final CruxCxpRuntime runtime;

  /// The protocol server the runtime started, or null before [start].
  LocalCxpServer? server;

  /// What peers' requests reach; the runtime asks it at each request. Until a
  /// test attaches one, every request is acknowledged as unsupported.
  CruxCxpRequestHandler? handler;

  /// Binds the port and writes the manifest. Never throws.
  Future<void> start() => runtime.start();

  /// Stops the runtime and releases it.
  Future<void> stop() => runtime.dispose();

  /// The bound port, or null when the runtime is not available.
  int? get boundPort => runtime.boundPort;

  /// Whether the server is bound and accepting peers.
  bool get isAvailable => runtime.isAvailable;

  /// Why the runtime is not available, or null.
  String? get unavailableReason => runtime.unavailableReason;

  /// This process's identity.
  PeerIdentity get selfIdentity => runtime.selfIdentity;
}

/// NetCrux's [NetcruxCxpRequestHandler], attached to [server] so the requests
/// a test's client sends reach it, as the mounted workspace publishes it in
/// the app.
class AttachedCxpHandler {
  /// Builds the handler and makes it the one [server] asks.
  AttachedCxpHandler({
    required CxpRuntimeRig server,
    required ProviderContainer rootContainer,
    required ActiveTabContainerLookup activeTabContainerLookup,
    EditorOpenService? editorService,
    NameResolver? nameResolver,
    SelectionFramer? selectionFramer,
  }) : handler = NetcruxCxpRequestHandler(
         rootContainer: rootContainer,
         activeTabContainerLookup: activeTabContainerLookup,
         editorService: editorService,
         nameResolver: nameResolver,
         selectionFramer: selectionFramer,
       ) {
    server.handler = handler;
  }

  /// The handler itself, for a test that calls its methods directly.
  final NetcruxCxpRequestHandler handler;

  /// Cancels any pending deferred highlight or framing.
  Future<void> dispose() => handler.dispose();
}
