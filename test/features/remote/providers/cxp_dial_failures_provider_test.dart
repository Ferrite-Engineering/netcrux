// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/remote/providers/cxp_dial_failures_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';

CxpDialFailure _failure(String peerId) => CxpDialFailure(
  peerId: peerId,
  host: '127.0.0.1',
  port: 4242,
  error: const _SocketErrorStub(),
  consecutiveFailures: 1,
  nextRetryAfterTicks: 0,
);

void main() {
  /// Subscribes to the provider and collects every data snapshot it emits.
  /// The `cxpServerHostProvider` dependency starts in loading and resolves
  /// asynchronously, so the stream provider rebuilds; `.future` cannot
  /// observe those successive states, but a persistent listener can.
  List<List<CxpDialFailure>> listen(ProviderContainer container) {
    final emissions = <List<CxpDialFailure>>[];
    final sub = container.listen(
      cxpDialFailuresProvider,
      (_, next) {
        if (next.hasValue) emissions.add(next.value!);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);
    return emissions;
  }

  test('yields an empty list when the server is absent', () async {
    final container = ProviderContainer(
      overrides: [cxpServerHostProvider.overrideWith(_NullHost.new)],
    );
    addTearDown(container.dispose);

    final emissions = listen(container);
    await pumpEventQueue();
    expect(emissions.last, isEmpty);
  });

  test(
    'yields an empty list when discovery is degraded (no dial-failure stream)',
    () async {
      final stub = _StubServer(hasFailures: false);
      addTearDown(stub.close);
      final container = ProviderContainer(
        overrides: [
          cxpServerHostProvider.overrideWith(() => _StaticHost(stub)),
        ],
      );
      addTearDown(container.dispose);

      final emissions = listen(container);
      await pumpEventQueue();
      expect(emissions.last, isEmpty);
    },
  );

  test('emits a fresh snapshot on every dial failure', () async {
    final stub = _StubServer();
    addTearDown(stub.close);
    final container = ProviderContainer(
      overrides: [cxpServerHostProvider.overrideWith(() => _StaticHost(stub))],
    );
    addTearDown(container.dispose);

    final emissions = <List<CxpDialFailure>>[];
    final sub = container.listen(
      cxpDialFailuresProvider,
      (_, next) {
        if (next.hasValue) emissions.add(next.value!);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    // The initial snapshot is empty — no peer has failed yet.
    await pumpEventQueue();
    expect(emissions.last, isEmpty);

    // A dial failure adds the peer to the connector's map; the provider
    // re-snapshots and surfaces it.
    stub
      ..current = <CxpDialFailure>[_failure('wavecrux-1')]
      ..push(_failure('wavecrux-1'));
    await pumpEventQueue();
    expect(emissions.last, hasLength(1));
    expect(emissions.last.single.peerId, 'wavecrux-1');

    // A peer that becomes reachable drops out of the connector's map; any
    // subsequent signal must re-read the map fresh, not accumulate.
    stub
      ..current = const <CxpDialFailure>[]
      ..push(_failure('simcrux-9'));
    await pumpEventQueue();
    expect(emissions.last, isEmpty);
  });
}

/// A test error stand-in so [_failure] does not pull in `dart:io`.
class _SocketErrorStub implements Exception {
  const _SocketErrorStub();
  @override
  String toString() => 'SocketErrorStub';
}

class _NullHost extends CxpServerHost {
  @override
  Future<NetcruxCxpServer?> build() async => null;
}

class _StaticHost extends CxpServerHost {
  _StaticHost(this._server);
  final NetcruxCxpServer _server;
  @override
  Future<NetcruxCxpServer?> build() async => _server;
}

/// A [NetcruxCxpServer] whose dial-failure surface is driven by the test
/// rather than by a live connector. [discovery] and [server] are left null
/// so the provider exercises its null-safe merge of the optional signals.
class _StubServer extends NetcruxCxpServer {
  _StubServer({this.hasFailures = true})
    : super(productVersion: '0.0.0-test', manifestDirectory: '');

  /// When false, [dialFailures] returns null — the degraded-discovery case
  /// where no connector was constructed.
  final bool hasFailures;
  final StreamController<CxpDialFailure> _controller =
      StreamController<CxpDialFailure>.broadcast();

  List<CxpDialFailure> current = const <CxpDialFailure>[];

  void push(CxpDialFailure failure) => _controller.add(failure);

  Future<void> close() => _controller.close();

  @override
  Stream<CxpDialFailure>? get dialFailures =>
      hasFailures ? _controller.stream : null;

  @override
  List<CxpDialFailure> get unreachablePeers => current;
}
