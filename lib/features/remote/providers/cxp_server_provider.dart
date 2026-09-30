// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/core/policy/org_cross_probe_allowlist.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cxp_server_provider.g.dart';

/// Whether this build has a CXP transport: loopback sockets and the
/// suite-shared discovery directory.
///
/// `false` in the browser, which has neither. There the server is never
/// constructed and the discovery directory is never resolved —
/// `sharedCxpManifestDirectory()` has no host environment to resolve against
/// in a browser and throws its "discovery unavailable" `StateError`.
/// Overridable so the browser branch is testable on the VM.
@Riverpod(keepAlive: true)
bool cxpTransportAvailable(Ref ref) => !kIsWeb;

/// Manifest directory provider — the suite-shared location resolved by
/// `sharedCxpManifestDirectory()` (crux_cxp). Tests override this with a
/// temp directory.
///
/// MUST be the bundle-independent shared location: an app-container-scoped
/// resolution (e.g. `getApplicationSupportDirectory()`) would put the
/// manifest somewhere no other suite product ever scans, making
/// cross-product discovery structurally impossible. Kept async for
/// override-compatibility.
@Riverpod(keepAlive: true)
Future<String> cxpManifestDirectory(Ref ref) async =>
    sharedCxpManifestDirectory();

/// The version this build reports in its CXP peer identity — the discovery
/// manifest and the handshake — which other suite apps show beside the peer
/// in their cross-probe panels.
///
/// The running build's version, from the same build info the About dialog
/// shows, so the Pro overlay reports its own. No compatibility logic reads
/// it, so a platform that cannot report a version gets `dev` rather than a
/// server that fails to start.
@Riverpod(keepAlive: true)
Future<String> netcruxProductVersion(Ref ref) async {
  try {
    return (await ref.watch(aboutBuildInfoProvider.future)).version;
  } on Object {
    return 'dev';
  }
}

/// Owns the lifecycle of the NetCrux CXP peer cross-probe server.
///
/// Watches [appSettingsProvider] so the server starts / stops in
/// response to the user flipping `cxpServerEnabled` or changing
/// `cxpServerPort` in Settings → CXP Cross-Probe. Disposing the
/// provider tears the server down cleanly (the auto-dispose path is
/// the WaveCrux pattern documented in the WaveCrux ARCHITECTURE
/// §6.4 description of root-scope providers).
@Riverpod(keepAlive: true)
class CxpServerHost extends _$CxpServerHost {
  @override
  Future<NetcruxCxpServer?> build() async {
    // No transport, no server — and nothing below may run: resolving the
    // manifest directory throws without a host environment.
    if (!ref.watch(cxpTransportAvailableProvider)) return null;
    // Rebuild the server ONLY when the CXP enable flag or bind port actually
    // changes — never on unrelated settings churn (panel-layout drags,
    // recent-files, theme, …). `selectAsync` filters the rebuild to those two
    // fields.
    //
    // Watching the whole `appSettingsProvider` here tore the server down and
    // recreated it on EVERY settings write. Combined with the schematic-mount
    // warm — which keeps this provider materialized throughout a
    // schematic session, exactly when panel-layout/auto-fit settings churn —
    // an invalidation landing while `server.start()` was still in flight
    // orphaned a bound-and-dialing server whose `onDispose` had not yet been
    // registered. Those never-stopped connectors piled up outbound sockets
    // (the cross-probe socket-leak regression) and the current provider value
    // ended up a server that had failed to (re)bind: no manifest, no peers.
    final (:enabled, :port) = await ref.watch(
      appSettingsProvider.selectAsync(
        (settings) => (
          enabled: settings.cxpServerEnabled,
          port: settings.cxpServerPort,
        ),
      ),
    );
    if (!enabled) return null;
    final manifestDir = await ref.watch(cxpManifestDirectoryProvider.future);
    final version = await ref.watch(netcruxProductVersionProvider.future);
    final server = NetcruxCxpServer(
      productVersion: version,
      manifestDirectory: manifestDir,
      port: port,
      // The floor, not the directories the user has opened. `LocalCxpServer`
      // holds one rule for both requests it screens, and a rooted one strips
      // the path hint from a `request_open_artifact` for a design NetCrux has
      // never opened — the very request that route exists to honour. A
      // `request_open_source` keeps its roots: `CxpInboundHandler` applies
      // the rooted rule to the path it is about to hand an editor.
      containment: kCxpOpenArtifactContainment,
    );
    // Register teardown the instant the instance exists — BEFORE the async
    // `start()`. If this build is superseded (or the container closes) while
    // `start()` is still in flight, `onDispose` is already wired, so the
    // partially-started server is stopped rather than orphaned. `stop()` tears
    // down whatever `start()` managed to create (bound socket, connector,
    // discovery, manifest) even from that partially-started state.
    ref.onDispose(() {
      // Best-effort teardown — the provider is being rebuilt or the
      // container is closing. Ignore errors; the next build will
      // create a fresh server.
      unawaited(server.stop());
    });
    await server.start();
    return server;
  }
}

/// Snapshot of a connected CXP peer for the cross-probe panel.
@immutable
class CxpPeerEntry {
  /// Creates a peer entry.
  const CxpPeerEntry({
    required this.identity,
    required this.host,
    required this.port,
  });

  /// Peer identity from the discovery manifest.
  final PeerIdentity identity;

  /// Host the peer is listening on.
  final String host;

  /// Port the peer's CXP server is bound to.
  final int port;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CxpPeerEntry &&
          other.identity == identity &&
          other.host == host &&
          other.port == port);

  @override
  int get hashCode => Object.hash(identity, host, port);
}

/// Stream of currently-known peers as observed by the discovery
/// watcher. The cross-probe panel `ref.watch`es this provider.
@Riverpod(keepAlive: true)
Stream<List<CxpPeerEntry>> cxpPeers(Ref ref) async* {
  final serverAsync = ref.watch(cxpServerHostProvider);
  final server = serverAsync.value;
  if (server == null || server.discovery == null) {
    yield const <CxpPeerEntry>[];
    return;
  }
  final discovery = server.discovery!;
  // The organization's allowlist, if it set one. Read here rather than in the
  // panel because this provider is the single source every cross-probe
  // surface enumerates — the panel and the schematic context menu both — so
  // filtering once is filtering everywhere.
  final allowlist = ref.watch(orgCrossProbeAllowlistProvider);
  // Emit the initial snapshot of already-known peers (the
  // discovery's start() does a synchronous initial scan before
  // returning), then propagate add/remove events as a fresh snapshot.
  yield _entries(
    discovery.peers,
    exclude: server.selfIdentity,
    allowlist: allowlist,
  );
  await for (final _ in discovery.events) {
    yield _entries(
      discovery.peers,
      exclude: server.selfIdentity,
      allowlist: allowlist,
    );
  }
}

List<CxpPeerEntry> _entries(
  List<CxpPeerManifest> manifests, {
  PeerIdentity? exclude,
  Set<String>? allowlist,
}) {
  final out = <CxpPeerEntry>[];
  for (final manifest in manifests) {
    // A peer the organization did not allow is not offered. Dropped here
    // rather than greyed in the panel: an allowlist is a restriction, and a
    // disabled entry naming a machine an engineer may not reach tells them
    // something the administrator chose not to.
    if (!crossProbeAllowed(allowlist, manifest.identity.productName)) {
      continue;
    }
    // Skip our own manifest so the cross-probe panel doesn't list
    // ourselves as a peer.
    if (exclude != null && manifest.identity.peerId == exclude.peerId) {
      continue;
    }
    out.add(
      CxpPeerEntry(
        identity: manifest.identity,
        host: manifest.host,
        port: manifest.port,
      ),
    );
  }
  return List.unmodifiable(out);
}
