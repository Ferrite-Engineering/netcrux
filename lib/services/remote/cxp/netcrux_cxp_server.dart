// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:netcrux/services/remote/cxp/netcrux_name_resolver.dart';

/// NetCrux-flavoured wrapper around `crux_cxp`'s [`LocalCxpServer`].
///
/// Owns the server lifecycle, the discovery [`CxpManifestWriter`], and the
/// [`CxpDiscovery`] watcher in a single value so callers only deal with
/// one thing. The CXP server is open-core: every NetCrux build runs it
/// (subject to the user's Settings → CXP Cross-Probe toggle) so the
/// receive-side cross-probe is suite-defining and free.
///
/// Lifecycle is start/stop only; the provider that owns this service is
/// responsible for wiring it through the app's runtime.
class NetcruxCxpServer {
  /// Creates a NetCrux CXP server bound to localhost.
  ///
  /// [productVersion] is reported in [PeerIdentity.productVersion]. The
  /// manifest directory defaults to `${appSupportDir}/crux/cxp/peers/`
  /// matching the cross-suite convention; tests pass a temp directory.
  ///
  /// The factory pair [serverFactory] / [discoveryFactory] is provided
  /// for tests so the unit tests can substitute fakes without touching
  /// the real socket layer. Production calls rely on the defaults that
  /// instantiate [`LocalCxpServer`] and [`CxpDiscovery`].
  NetcruxCxpServer({
    required this.productVersion,
    required this.manifestDirectory,
    int port = 0,
    NameResolver? nameResolver,
    CxpPathContainment? containment,
    LocalCxpServer Function(
      PeerIdentity self,
      int port,
      NameResolver resolver,
      CxpPathContainment containment,
    )?
    serverFactory,
    CxpManifestWriter Function(String dir)? manifestWriterFactory,
    CxpDiscovery Function(String dir)? discoveryFactory,
    DateTime Function()? clock,
    int Function()? pidFactory,
  }) : containment = containment ?? const CxpPathContainment(),
       _requestedPort = port,
       _nameResolver = nameResolver ?? const NetcruxNameResolver(),
       _serverFactory = serverFactory ?? _defaultServerFactory,
       _manifestWriterFactory =
           manifestWriterFactory ?? _defaultManifestWriterFactory,
       _discoveryFactory = discoveryFactory ?? _defaultDiscoveryFactory,
       _clock = clock ?? DateTime.now,
       _pidFactory = pidFactory ?? _defaultPid;

  /// NetCrux's reported version string. The server embeds this in its
  /// [PeerIdentity.productVersion].
  final String productVersion;

  /// Directory holding `<peer_id>.json` manifests. Production:
  /// `${appSupportDir}/crux/cxp/peers/`.
  final String manifestDirectory;

  /// The receiver-side rule (CXP §11) every peer-supplied path is checked
  /// against, handed to [LocalCxpServer] so a `request_open_source` or a
  /// `request_open_artifact` hint is screened before the product sees it.
  ///
  /// The shared layer can only check the value that arrived on the wire;
  /// `CxpInboundHandler` checks the value NetCrux is about to load or hand to
  /// an editor, under the rule that route keeps. The default is the floor
  /// (absolute, well-formed), and the provider layer supplies the floor too:
  /// one rule screens both requests here, and the artifact request's hint
  /// must not be rooted in the directories the user has opened.
  final CxpPathContainment containment;

  final int _requestedPort;
  final NameResolver _nameResolver;
  final LocalCxpServer Function(
    PeerIdentity self,
    int port,
    NameResolver resolver,
    CxpPathContainment containment,
  )
  _serverFactory;
  final CxpManifestWriter Function(String dir) _manifestWriterFactory;
  final CxpDiscovery Function(String dir) _discoveryFactory;
  final DateTime Function() _clock;
  final int Function() _pidFactory;

  LocalCxpServer? _server;
  CxpManifestWriter? _manifestWriter;
  CxpDiscovery? _discovery;
  CxpPeerConnector? _connector;
  PeerIdentity? _identity;
  var _running = false;
  // Set by [stop]. A [stop] can land while [start] is still awaiting its bind
  // (the owning provider was superseded mid-start); this flag makes the
  // in-flight [start] unwind instead of finishing the handshake wiring and
  // leaving a live listener + dialing connector nothing will ever tear down.
  var _stopped = false;
  String? _unavailableReason;

  /// The underlying CXP server, or `null` before [start].
  LocalCxpServer? get server => _server;

  /// The discovery watcher, or `null` before [start].
  CxpDiscovery? get discovery => _discovery;

  /// The local peer identity once [start] has computed it; `null` before.
  PeerIdentity? get selfIdentity => _identity;

  /// True between [start] and [stop].
  bool get isRunning => _running;

  /// True when the server is running **and** bound to a port — i.e. the
  /// cross-probe receive side is actually reachable. False after a bind
  /// failure, before [start], or after [stop].
  bool get isAvailable => _running && _server?.boundPort != null;

  /// A human-readable reason the cross-probe is unavailable or degraded
  /// (bind failure, manifest-dir permission failure), or `null` when the
  /// server came up cleanly. Surfaced by the UI as a non-fatal status.
  String? get unavailableReason => _unavailableReason;

  /// The port the server is bound to, or `null` before [start].
  int? get boundPort => _server?.boundPort;

  /// Broadcast stream of outbound dial failures from the peer connector —
  /// one event per failed attempt to reach a discovered peer's server.
  /// `null` before [start] / after [stop], or when peer discovery is
  /// degraded (no connector was constructed).
  ///
  /// A dial failure means the manifest was found but the socket could not
  /// be established, i.e. one-way connectivity: the peer is present in
  /// discovery yet unreachable. Surfaced by the cross-probe panel so an
  /// unreachable peer is not indistinguishable from an absent one.
  Stream<CxpDialFailure>? get dialFailures => _connector?.dialFailures;

  /// Snapshot of the most-recent dial failure per currently-unreachable
  /// peer. A peer leaves this list once its handshake succeeds or its
  /// manifest is removed. Empty when every discovered peer is reachable,
  /// when none has been discovered, or before [start].
  List<CxpDialFailure> get unreachablePeers =>
      _connector?.lastDialFailures.values.toList(growable: false) ??
      const <CxpDialFailure>[];

  /// Start the server, write the discovery manifest, and start watching
  /// the manifest directory for peers.
  Future<void> start() async {
    if (_running || _stopped) return;
    _unavailableReason = null;
    final identity = _buildIdentity();
    _identity = identity;
    final server = _serverFactory(
      identity,
      _requestedPort,
      _nameResolver,
      containment,
    );
    _server = server;
    // A bind failure (ephemeral port unavailable / firewall /
    // sandbox) must degrade to "cross-probe unavailable", never throw an
    // uncaught SocketException onto the launch path.
    try {
      await server.start();
    } on Object catch (e) {
      await _abortStart('CXP cross-probe unavailable (bind failed): $e');
      return;
    }
    // A stop() landed while we were binding: unwind rather than proceed to
    // wire up a manifest + connector nobody will tear down.
    if (_stopped) {
      await server.stop();
      _server = null;
      _identity = null;
      return;
    }
    final boundPort = server.boundPort;
    if (boundPort == null) {
      await _abortStart('CXP cross-probe unavailable: server did not bind.');
      return;
    }
    _running = true;
    // A manifest-dir permission failure degrades discovery but does
    // not tear down the (already-bound) server nor crash — record a warning.
    try {
      final writer = _manifestWriterFactory(manifestDirectory);
      _manifestWriter = writer;
      await writer.write(
        identity: identity,
        host: '127.0.0.1',
        port: boundPort,
      );
      final discovery = _discoveryFactory(manifestDirectory);
      _discovery = discovery;
      await discovery.start();
      // Dial every discovered non-self peer so its server sees an inbound
      // Hello (its symmetric connector dials us back, filling OUR
      // connectedPeers). Passing `server:` additionally merges each
      // link's inbound frames into this server's own dispatch stream and
      // registers the link as a reply route (`CxpServer.attachLinkedPeer`),
      // so a peer we merely dialed — and who never dials us back — can
      // still reach our request handlers, get an ack back, and receive
      // our notify_selection broadcasts via the connector's
      // auto-subscribe. Without `server:` the connector only proves
      // presence: link traffic arrives on the connector's own client
      // socket and nobody is listening to it.
      _connector = CxpPeerConnector(
        selfIdentity: identity,
        discovery: discovery,
        server: server,
      )..start();
    } on Object catch (e) {
      _unavailableReason = 'CXP peer discovery degraded: $e';
    }
    // A stop() may have landed while we were writing the manifest / starting
    // discovery. Tear back down so the discovery watcher, connector, and
    // manifest we just created don't outlive the stop().
    if (_stopped) await stop();
  }

  /// Unwinds a partially-started server after a bind failure, recording
  /// [reason] and leaving the service in the not-running / unavailable state.
  Future<void> _abortStart(String reason) async {
    _unavailableReason = reason;
    try {
      await _server?.stop();
    } on Object {
      // Best-effort — the server never bound, so this is usually a no-op.
    }
    _server = null;
    _identity = null;
    _running = false;
  }

  /// Stop the server, remove the manifest file, and tear down the
  /// discovery watcher.
  ///
  /// Deliberately NOT gated on [_running]: a stop() can arrive on a server
  /// whose [start] is still in flight (the owning provider was invalidated
  /// mid-start). Tearing down whatever [start] has created so far — bound
  /// listen socket, dialing connector, discovery watcher, manifest — is what
  /// stops a superseded start from orphaning a live listener + connector that
  /// nothing else would ever close (the socket-leak regression). Fields are
  /// captured and nulled first so a concurrent in-flight [start] observes the
  /// torn-down state (and its own `_stopped` re-checks unwind it). Idempotent.
  Future<void> stop() async {
    _stopped = true;
    _running = false;
    final connector = _connector;
    _connector = null;
    final discovery = _discovery;
    _discovery = null;
    final manifestWriter = _manifestWriter;
    _manifestWriter = null;
    final server = _server;
    _server = null;
    _identity = null;
    await connector?.stop();
    await discovery?.stop();
    await manifestWriter?.remove();
    await server?.stop();
  }

  /// Sends [request] to [peerId] and waits for the peer's
  /// [RequestHighlightAck], so the caller can surface a rejected send. Returns
  /// `(delivered: false, ack: null)` when the peer is unreachable, and
  /// `(delivered: true, ack: null)` when the send left but no ack arrived within
  /// [timeout]. Correlates by "the next RequestHighlightAck from [peerId]",
  /// which is unambiguous because such an ack is only ever a reply to a
  /// request_highlight and directed sends are the sole source of them.
  Future<({bool delivered, RequestHighlightAck? ack})> requestHighlight(
    String peerId,
    RequestHighlight request, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final localServer = server;
    if (localServer == null) return (delivered: false, ack: null);
    final completer = Completer<RequestHighlightAck>();
    final sub = localServer.inbound.listen((inbound) {
      if (inbound.from.peerId == peerId &&
          inbound.message is RequestHighlightAck &&
          !completer.isCompleted) {
        completer.complete(inbound.message as RequestHighlightAck);
      }
    });
    final delivered = localServer.sendTo(peerId, request);
    if (!delivered) {
      await sub.cancel();
      return (delivered: false, ack: null);
    }
    RequestHighlightAck? ack;
    try {
      ack = await completer.future.timeout(timeout);
    } on TimeoutException {
      ack = null;
    } finally {
      await sub.cancel();
    }
    return (delivered: true, ack: ack);
  }

  PeerIdentity _buildIdentity() {
    final pid = _pidFactory();
    final stamp = _clock().millisecondsSinceEpoch;
    return PeerIdentity(
      peerId: 'netcrux-$pid-$stamp',
      productName: 'netcrux',
      productVersion: productVersion,
    );
  }

  static LocalCxpServer _defaultServerFactory(
    PeerIdentity self,
    int port,
    NameResolver resolver,
    CxpPathContainment containment,
  ) {
    return LocalCxpServer(
      selfIdentity: self,
      nameResolver: resolver,
      port: port,
      containment: containment,
    );
  }

  static CxpManifestWriter _defaultManifestWriterFactory(String dir) {
    return CxpManifestWriter(manifestDirectory: dir);
  }

  static CxpDiscovery _defaultDiscoveryFactory(String dir) {
    return CxpDiscovery(manifestDirectory: dir);
  }

  static int _defaultPid() => pid;
}
