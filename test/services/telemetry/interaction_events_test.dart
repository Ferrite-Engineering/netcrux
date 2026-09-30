// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `trace.used` and `cxp.crossprobe`, on their production seams.
//
// The trace counter comes out of `WorkspaceActionDispatcher._dispatchTrace`,
// which is where the Show Fanin / Show Fanout actions land from all three
// discovery surfaces (keyboard, menu bar, command palette). The cross-probe
// counter comes out of `CxpInboundHandler._resolveAndAct`, the one seam both
// the acked `request_highlight` and the fire-and-forget `notify_selection`
// pass through.
//
// The cross-probe test asserts the honored=false case as loudly as the
// honored=true one, because that is the whole point of the property: a probe a
// peer sent and NetCrux could not act on is the suite network-effect failure
// the funnel exists to surface, and dropping it would make the metric read
// healthy exactly when it is not.

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/workspace/services/workspace_action_dispatcher.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/cxp_inbound_handler.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import 'package:netcrux/services/telemetry/telemetry_event_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  List<String> get names => [for (final e in events) e.name];

  Iterable<TelemetryEvent> all(String name) =>
      events.where((e) => e.name == name);

  int count(String name) => all(name).length;
}

/// Fails unless every property of [event] is declared by its catalog entry
/// with a value from the declared vocabulary.
void _assertInCatalog(TelemetryEvent event) {
  final entry = kNetcruxEventCatalog.firstWhere(
    (e) => e.name == event.name,
    orElse: () => throw StateError('${event.name} is not in the catalog'),
  );
  event.properties.forEach((key, value) {
    expect(entry.propertyKeys, contains(key));
    if (entry.enumeratedValues.containsKey(key)) {
      expect(entry.enumeratedValues[key], contains(value));
    } else if (entry.boolProperties.contains(key)) {
      expect(value, isA<bool>());
    } else {
      expect(value, isA<int>());
    }
  });
}

NetlistModel _model() {
  const top = Module(
    name: 'top',
    attributes: <String, String>{'top': '1'},
    ports: <String, Port>{},
    cells: <String, Cell>{
      'u_cpu': Cell(
        name: 'u_cpu',
        type: 'cpu',
        parameters: <String, String>{},
        attributes: <String, String>{},
        portDirections: <String, PortDirection>{'CLK': PortDirection.input},
        connections: <String, List<BitRef>>{
          'CLK': <BitRef>[NetBit(1)],
        },
      ),
    },
    nets: <String, Net>{},
  );
  const cpu = Module(
    name: 'cpu',
    attributes: <String, String>{},
    ports: <String, Port>{},
    cells: <String, Cell>{},
    nets: <String, Net>{},
  );
  return const NetlistModel(
    creator: 'test',
    modules: <String, Module>{'top': top, 'cpu': cpu},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingTelemetryService telemetry;

  setUp(() {
    telemetry = _RecordingTelemetryService();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // ── trace.used ──────────────────────────────────────────────────────────────

  group('trace.used', () {
    Future<(WorkspaceActionDispatcher, BuildContext)> pumpDispatcher(
      WidgetTester tester,
    ) async {
      late WorkspaceActionDispatcher dispatcher;
      late BuildContext hostContext;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                hostContext = context;
                dispatcher = WorkspaceActionDispatcher(
                  ref: ref,
                  openProject: () async {},
                  openSourceFiles: () async {},
                  openNetlistJson: () async {},
                  openWorkspaceFlow: () async {},
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return (dispatcher, hostContext);
    }

    testWidgets('Show Fanin and Show Fanout each record their kind', (
      tester,
    ) async {
      final (dispatcher, context) = await pumpDispatcher(tester);

      dispatcher
        ..dispatch(context, NetcruxAction.showFanin)
        ..dispatch(context, NetcruxAction.showFanout);
      await tester.pump();

      expect(telemetry.count('trace.used'), 2);
      expect(
        [for (final e in telemetry.all('trace.used')) e.properties['kind']],
        <String>['fanin', 'fanout'],
      );
      telemetry.all('trace.used').forEach(_assertInCatalog);
    });

    testWidgets('a trace with nothing selected still counts as asked-for', (
      tester,
    ) async {
      // The controller no-ops on an empty selection, but the user did ask for
      // a trace, and "asked and got nothing" is a signal worth having.
      final (dispatcher, context) = await pumpDispatcher(tester);
      dispatcher.dispatch(context, NetcruxAction.showFanin);
      await tester.pump();

      expect(telemetry.count('trace.used'), 1);
    });

    test('every TraceOverlayMode is a catalog token', () {
      final entry = kNetcruxEventCatalog.firstWhere(
        (e) => e.name == 'trace.used',
      );
      for (final mode in TraceOverlayMode.values) {
        expect(
          entry.enumeratedValues['kind'],
          contains(telemetryEnumToken(mode)),
        );
      }
    });
  });

  // ── cxp.crossprobe ──────────────────────────────────────────────────────────

  group('cxp.crossprobe (inbound)', () {
    Future<
      ({
        NetcruxCxpServer server,
        LocalCxpClient client,
        ProviderContainer rootContainer,
        ProviderContainer tabContainer,
        Directory tmp,
        CxpInboundHandler handler,
      })
    >
    setup({bool loadModel = true}) async {
      final tmp = Directory.systemTemp.createTempSync('cxp_telemetry_');
      final server = NetcruxCxpServer(
        productVersion: '0.0.0-test',
        manifestDirectory: '${tmp.path}/peers',
      );
      await server.start();

      final client = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: 'wavecrux-telemetry-test',
          productName: 'wavecrux',
          productVersion: '0.0.0-test',
        ),
      );
      await client.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: cxpProcessAuthToken,
      );

      final rootContainer = ProviderContainer(
        overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
      );
      final tabContainer = ProviderContainer(parent: rootContainer);
      if (loadModel) {
        tabContainer.read(hierarchyTreeProvider.notifier).setModel(_model());
      }
      final handler = CxpInboundHandler(
        server: server.server!,
        rootContainer: rootContainer,
        activeTabContainerLookup: () => tabContainer,
      );

      addTearDown(() async {
        await handler.dispose();
        await client.dispose();
        await server.stop();
        tabContainer.dispose();
        rootContainer.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } on FileSystemException {
          // Best effort.
        }
      });

      return (
        server: server,
        client: client,
        rootContainer: rootContainer,
        tabContainer: tabContainer,
        tmp: tmp,
        handler: handler,
      );
    }

    /// Sends one `request_highlight` and waits for NetCrux's ack.
    Future<RequestHighlightAck> probe(
      LocalCxpClient client, {
      required String path,
      ElementKind kind = ElementKind.instance,
    }) async {
      final ackFuture = client.inbound.firstWhere(
        (m) => m.message is RequestHighlightAck,
      );
      client.send(
        RequestHighlight(
          element: ElementId(kind: kind, path: path),
        ),
      );
      final inbound = await ackFuture.timeout(const Duration(seconds: 2));
      return inbound.message as RequestHighlightAck;
    }

    test('a probe NetCrux acts on records honored: true', () async {
      final boot = await setup();

      final ack = await probe(boot.client, path: 'top.u_cpu:cell');
      expect(ack.honored, isTrue);

      expect(telemetry.count('cxp.crossprobe'), 1);
      final event = telemetry.events.first;
      expect(event.properties, <String, Object?>{
        'direction': 'inbound',
        'honored': true,
      });
      _assertInCatalog(event);
    });

    test('a probe NetCrux cannot act on records honored: false', () async {
      // The failure the funnel exists to surface. Losing it would make the
      // cross-probe metric read healthy exactly when the suite handshake is
      // broken.
      final boot = await setup();

      final ack = await probe(boot.client, path: 'top.no_such_instance:cell');
      expect(ack.honored, isFalse);

      expect(telemetry.count('cxp.crossprobe'), 1);
      expect(telemetry.events.first.properties['honored'], false);
    });

    test('the event carries no element path and no peer identity', () async {
      final boot = await setup();
      await probe(boot.client, path: 'top.u_cpu:cell');

      final serialized = telemetry.events.first.toString();
      expect(serialized, isNot(contains('u_cpu')));
      expect(serialized, isNot(contains('wavecrux-telemetry-test')));
      expect(telemetry.events.first.properties.keys, <String>[
        'direction',
        'honored',
      ]);
    });

    test('a probe arriving with no design loaded still counts', () async {
      final boot = await setup(loadModel: false);

      await probe(boot.client, path: 'top.u_cpu:cell');

      expect(telemetry.count('cxp.crossprobe'), 1);
      expect(telemetry.events.first.properties['honored'], false);
    });
  });
}
