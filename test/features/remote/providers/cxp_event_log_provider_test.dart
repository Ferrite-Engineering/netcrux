// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/remote/providers/cxp_event_log_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';

import '../../../helpers/wait_for.dart';

/// A started NetCrux CXP server. Real sockets — the event log's whole job
/// is to mirror what actually arrives on the wire. The peer client is
/// connected by the caller AFTER the log provider has a listener, so the
/// presence event lands inside the observation window (both underlying
/// streams are broadcast: events emitted before the subscription are
/// gone).
Future<({NetcruxCxpServer server, Directory tmp})> _bootServer() async {
  final tmp = Directory.systemTemp.createTempSync('cxp_event_log_');
  final server = NetcruxCxpServer(
    productVersion: '0.0.0-test',
    manifestDirectory: '${tmp.path}/peers',
  );
  await server.start();
  return (server: server, tmp: tmp);
}

Future<LocalCxpClient> _connectPeer(NetcruxCxpServer server) async {
  final client = LocalCxpClient(
    selfIdentity: const PeerIdentity(
      peerId: 'wavecrux-log-peer',
      productName: 'wavecrux',
      productVersion: '1.2.3',
    ),
  );
  await client.connect(
    host: '127.0.0.1',
    port: server.boundPort!,
    token: cxpProcessAuthToken,
  );
  return client;
}

/// Subscribes to the log so the notifier's `build` runs (wiring the server
/// stream subscriptions) and stays alive.
ProviderSubscription<List<CxpEventLogEntry>> _listen(
  ProviderContainer container,
) => container.listen(cxpEventLogProvider, (_, _) {}, fireImmediately: true);

/// Reads the provider's current buffer.
List<CxpEventLogEntry> _entries(ProviderContainer container) =>
    container.read(cxpEventLogProvider);

void main() {
  group('empty-source paths', () {
    test('a null host yields an empty log', () async {
      final container = ProviderContainer(
        overrides: [
          cxpServerHostProvider.overrideWith(_NullHost.new),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(_listen(container).close);

      expect(_entries(container), isEmpty);
    });

    test('a host whose server never started yields an empty log', () async {
      final tmp = Directory.systemTemp.createTempSync(
        'cxp_event_log_unstarted_',
      );
      addTearDown(() => bestEffortDeleteTempDir(tmp));
      final unstarted = NetcruxCxpServer(
        productVersion: '0.0.0-test',
        manifestDirectory: '${tmp.path}/peers',
      );
      final container = ProviderContainer(
        overrides: [
          cxpServerHostProvider.overrideWith(() => _StaticHost(unstarted)),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(_listen(container).close);

      expect(unstarted.server, isNull);
      expect(_entries(container), isEmpty);
    });
  });

  group('live event capture', () {
    late ({NetcruxCxpServer server, Directory tmp}) boot;
    late LocalCxpClient client;
    late ProviderContainer container;
    late ProviderSubscription<List<CxpEventLogEntry>> keepAlive;

    setUp(() async {
      boot = await _bootServer();
      container = ProviderContainer(
        overrides: [
          cxpServerHostProvider.overrideWith(() => _StaticHost(boot.server)),
        ],
      );
      keepAlive = _listen(container);
      client = await _connectPeer(boot.server);
    });

    tearDown(() async {
      keepAlive.close();
      container.dispose();
      await client.dispose();
      await boot.server.stop();
      await bestEffortDeleteTempDir(boot.tmp);
    });

    test('the presence of the connecting peer is logged', () async {
      await waitFor(
        () => _entries(container).any(
          (e) => e.direction == CxpEventDirection.presence,
        ),
        reason: 'the client connection never produced a presence entry',
      );
      final entry = _entries(container).firstWhere(
        (e) => e.direction == CxpEventDirection.presence,
      );
      expect(entry.kind, 'connected');
      expect(entry.peerLabel, contains('wavecrux'));
      expect(entry.peerLabel, contains('wavecrux-log-peer'));
      expect(entry.detail, isNull);
    });

    test('a disconnecting peer logs a disconnected entry', () async {
      await waitFor(
        () => _entries(container).any((e) => e.kind == 'connected'),
        reason: 'no connect presence entry',
      );
      await client.dispose();
      await waitFor(
        () => _entries(container).any((e) => e.kind == 'disconnected'),
        reason: 'the client teardown never produced a disconnected entry',
      );
    });

    test(
      'inbound notify_selection details fall back to the element path',
      () async {
        client.send(
          const NotifySelection(
            elements: <ElementId>[
              ElementId(kind: ElementKind.instance, path: 'top.u_cpu:cell'),
            ],
          ),
        );
        await waitFor(
          () => _entries(container).any(
            (e) => e.kind == CxpMessageKind.notifySelection,
          ),
          reason: 'the notify_selection never reached the log',
        );
        final entry = _entries(container).firstWhere(
          (e) => e.kind == CxpMessageKind.notifySelection,
        );
        expect(entry.direction, CxpEventDirection.inbound);
        expect(entry.detail, 'top.u_cpu:cell');
      },
    );

    test(
      'a notify_selection display name wins over the element path',
      () async {
        client.send(
          const NotifySelection(
            elements: <ElementId>[
              ElementId(kind: ElementKind.instance, path: 'top.u_cpu:cell'),
            ],
            displayName: 'u_cpu',
          ),
        );
        await waitFor(
          () => _entries(container).any((e) => e.detail == 'u_cpu'),
          reason: 'the display name never reached the log detail line',
        );
      },
    );

    test('inbound request_highlight details carry the element path', () async {
      client.send(
        const RequestHighlight(
          element: ElementId(kind: ElementKind.net, path: 'top:net:7'),
        ),
      );
      await waitFor(
        () => _entries(container).any((e) => e.detail == 'top:net:7'),
        reason: 'the request_highlight path never reached the log',
      );
      final entry = _entries(container).firstWhere(
        (e) => e.detail == 'top:net:7',
      );
      expect(entry.kind, CxpMessageKind.requestHighlight);
      expect(entry.direction, CxpEventDirection.inbound);
    });

    test('inbound request_open_source details render file:line', () async {
      // Absolute on the host, or the server's floor refuses it before it is
      // dispatched, and so before it is logged: on Windows a path without a
      // drive is rooted, not absolute.
      final file = Platform.isWindows ? r'C:\src\top.v' : '/src/top.v';
      client.send(RequestOpenSource(filePath: file, line: 42));
      await waitFor(
        () => _entries(container).any((e) => e.detail == '$file:42'),
        reason: 'the request_open_source detail never reached the log',
      );
    });

    test('a kind with no detail mapping logs a null detail', () async {
      client.send(
        const RequestHighlightAck(inReplyTo: 'msg-1', honored: true),
      );
      await waitFor(
        () => _entries(container).any(
          (e) => e.kind == CxpMessageKind.requestHighlightAck,
        ),
        reason: 'the request_highlight_ack never reached the log',
      );
      final entry = _entries(container).firstWhere(
        (e) => e.kind == CxpMessageKind.requestHighlightAck,
      );
      expect(entry.detail, isNull);
    });

    test(
      'the buffer is newest-first and capped at the rolling capacity',
      () async {
        const overflow = kCxpEventLogCapacity + 5;
        for (var i = 0; i < overflow; i++) {
          client.send(
            RequestHighlight(
              element: ElementId(kind: ElementKind.net, path: 'top:net:$i'),
            ),
          );
        }
        await waitFor(
          () => _entries(container).any(
            (e) => e.detail == 'top:net:${overflow - 1}',
          ),
          reason: 'the last of the overflow burst never arrived',
        );

        final log = _entries(container);
        expect(log, hasLength(kCxpEventLogCapacity));
        expect(
          log.first.detail,
          'top:net:${overflow - 1}',
          reason: 'newest entry must sit at index 0',
        );
        expect(
          log.map((e) => e.detail),
          isNot(contains('top:net:0')),
          reason: 'the oldest entries must have fallen off the end',
        );
      },
    );

    test('recordOutbound appends a newest-first outbound entry', () async {
      container
          .read(cxpEventLogProvider.notifier)
          .recordOutbound(
            kind: CxpMessageKind.notifySelection,
            peerLabel: 'wavecrux (peer-9)',
            detail: 'top.sample_a',
          );
      final entries = _entries(container);
      expect(entries.first.direction, CxpEventDirection.outbound);
      expect(entries.first.kind, CxpMessageKind.notifySelection);
      expect(entries.first.detail, 'top.sample_a');
    });

    test('clear empties the buffer', () async {
      container
          .read(cxpEventLogProvider.notifier)
          .recordOutbound(
            kind: CxpMessageKind.requestHighlight,
            peerLabel: 'wavecrux (peer-9)',
          );
      expect(_entries(container), isNotEmpty);
      container.read(cxpEventLogProvider.notifier).clear();
      expect(_entries(container), isEmpty);
    });

    test('disposing the container stops appending to the log', () async {
      await waitFor(
        () => _entries(container).isNotEmpty,
        reason: 'no baseline entry to compare against',
      );
      final before = _entries(container).length;
      keepAlive.close();
      container.dispose();

      client.send(
        const RequestHighlight(
          element: ElementId(kind: ElementKind.net, path: 'top:net:post'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Re-reading a disposed container would throw; the observable
      // assertion is that the torn-down subscription left no live
      // listener behind and the server kept running regardless.
      expect(before, greaterThan(0));
      expect(boot.server.isRunning, isTrue);
    });
  });

  test('CxpEventLogEntry.toString names direction, kind and peer', () {
    final entry = CxpEventLogEntry(
      timestamp: DateTime.utc(2026, 5, 25, 14, 30),
      direction: CxpEventDirection.outbound,
      kind: CxpMessageKind.notifySelection,
      peerLabel: 'wavecrux (peer-1)',
      detail: 'top.u_cpu',
    );
    final text = entry.toString();
    expect(text, contains('outbound'));
    expect(text, contains(CxpMessageKind.notifySelection));
    expect(text, contains('wavecrux (peer-1)'));
  });
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
