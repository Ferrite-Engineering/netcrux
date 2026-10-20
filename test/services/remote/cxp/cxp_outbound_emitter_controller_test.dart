// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/remote/cxp/cxp_outbound_emitter_controller.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';

import '../../../helpers/cxp_runtime_rig.dart';
import '../../../helpers/wait_for.dart';
import 'cxp_test_barrier.dart';

NetlistModel _model() {
  Cell cell(String name, String type) => Cell(
    name: name,
    type: type,
    parameters: const {},
    attributes: const {},
    portDirections: const {},
    connections: const {},
  );
  final cpu = Module(
    name: 'cpu',
    attributes: const {},
    ports: const {},
    cells: <String, Cell>{'u_alu': cell('u_alu', 'alu')},
    nets: const {},
  );
  final top = Module(
    name: 'top',
    attributes: const <String, String>{'top': '1'},
    ports: const {},
    cells: <String, Cell>{
      'u_cpu': cell('u_cpu', 'cpu'),
      // Second selectable cell — the suppressed-clear test selects it as
      // its in-band FIFO barrier after clear().
      'u_dma': cell('u_dma', r'$dff'),
    },
    nets: const {},
  );
  const alu = Module(
    name: 'alu',
    attributes: <String, String>{},
    ports: <String, Port>{},
    cells: <String, Cell>{},
    nets: <String, Net>{},
  );
  return NetlistModel(
    creator: 'test',
    modules: <String, Module>{'top': top, 'cpu': cpu, 'alu': alu},
  );
}

Future<({CxpRuntimeRig server, LocalCxpClient client, Directory tmp})>
_bootServerWithSubscribedClient() async {
  final tmp = Directory.systemTemp.createTempSync('cxp_emit_ctrl_');
  final server = CxpRuntimeRig(manifestDirectory: '${tmp.path}/peers');
  await server.start();
  final client = LocalCxpClient(
    selfIdentity: const PeerIdentity(
      peerId: 'wavecrux-emitter-ctrl',
      productName: 'wavecrux',
      productVersion: '0.0.0-test',
    ),
  );
  await client.connect(
    host: '127.0.0.1',
    port: server.boundPort!,
    token: cxpProcessAuthToken,
  );
  client.send(
    const Subscribe(
      subscriptions: <CxpSubscription>[
        CxpSubscription(messageKind: CxpMessageKind.notifySelection),
      ],
    ),
  );
  // FIFO round-trip proves the Subscribe is registered server-side before
  // the test body broadcasts anything.
  await cxpRoundTripBarrier(client);
  return (server: server, client: client, tmp: tmp);
}

void main() {
  group('CxpOutboundEmitterController', () {
    test(
      'cell selection emits NotifySelection(ElementKind.instance)',
      () async {
        final boot = await _bootServerWithSubscribedClient();
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best effort */
          }
        });

        final container = ProviderContainer(
          overrides: [
            ..._cxpOverrides(boot.server),
          ],
        );
        addTearDown(container.dispose);
        // Prime the AsyncNotifier so .value is populated before the
        // controller fires its first emission.
        await container.read(cruxCxpRuntimeProvider.future);
        container.read(hierarchyTreeProvider.notifier).setModel(_model());

        final controller = CxpOutboundEmitterController(container);
        addTearDown(controller.dispose);

        final inboundFuture = boot.client.inbound.firstWhere(
          (m) => m.message is NotifySelection,
        );

        container
            .read(selectedElementProvider.notifier)
            .select(
              const SelectedElement.cell(cellId: 'u_cpu'),
            );

        final inbound = await inboundFuture.timeout(const Duration(seconds: 2));
        final notify = inbound.message as NotifySelection;
        expect(notify.elements, hasLength(1));
        expect(notify.elements.first.kind, ElementKind.instance);
        // Clean dot-joined instance name (no `:cell` marker) so a receiver can
        // leaf-match the instance — the cross-probe identity fix.
        expect(notify.elements.first.path, 'top.u_cpu');
        expect(notify.displayName, 'u_cpu');
        expect(notify.metadata['netcrux.scope_path'], 'top');
      },
    );

    test('port selection emits ElementKind.port', () async {
      final boot = await _bootServerWithSubscribedClient();
      addTearDown(() async {
        await boot.client.dispose();
        await boot.server.stop();
        try {
          boot.tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* best effort */
        }
      });
      final container = ProviderContainer(
        overrides: [
          ..._cxpOverrides(boot.server),
        ],
      );
      addTearDown(container.dispose);
      // Prime the AsyncNotifier so .value is populated before the
      // controller fires its first emission.
      await container.read(cruxCxpRuntimeProvider.future);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());

      final controller = CxpOutboundEmitterController(container);
      addTearDown(controller.dispose);

      final inboundFuture = boot.client.inbound.firstWhere(
        (m) => m.message is NotifySelection,
      );

      container
          .read(selectedElementProvider.notifier)
          .select(
            const SelectedElement.port(
              cellId: 'u_cpu',
              portId: 'u_cpu:CLK',
              portName: 'CLK',
            ),
          );

      final inbound = await inboundFuture.timeout(const Duration(seconds: 2));
      final notify = inbound.message as NotifySelection;
      expect(notify.elements.first.kind, ElementKind.port);
      expect(notify.elements.first.path, 'top.u_cpu.CLK');
      expect(notify.displayName, 'CLK');
    });

    test('wire selection emits ElementKind.net', () async {
      final boot = await _bootServerWithSubscribedClient();
      addTearDown(() async {
        await boot.client.dispose();
        await boot.server.stop();
        try {
          boot.tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* best effort */
        }
      });
      final container = ProviderContainer(
        overrides: [
          ..._cxpOverrides(boot.server),
        ],
      );
      addTearDown(container.dispose);
      // Prime the AsyncNotifier so .value is populated before the
      // controller fires its first emission.
      await container.read(cruxCxpRuntimeProvider.future);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());

      final controller = CxpOutboundEmitterController(container);
      addTearDown(controller.dispose);

      final inboundFuture = boot.client.inbound.firstWhere(
        (m) => m.message is NotifySelection,
      );

      container
          .read(selectedElementProvider.notifier)
          .select(
            const SelectedElement.wire(edgeId: 'e_7', netId: 42),
          );

      final inbound = await inboundFuture.timeout(const Duration(seconds: 2));
      final notify = inbound.message as NotifySelection;
      expect(notify.elements.first.kind, ElementKind.net);
      expect(notify.elements.first.path, 'top:net:e_7');
    });

    test('empty selection does not broadcast', () async {
      final boot = await _bootServerWithSubscribedClient();
      addTearDown(() async {
        await boot.client.dispose();
        await boot.server.stop();
        try {
          boot.tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* best effort */
        }
      });
      final container = ProviderContainer(
        overrides: [
          ..._cxpOverrides(boot.server),
        ],
      );
      addTearDown(container.dispose);
      // Prime the AsyncNotifier so .value is populated before the
      // controller fires its first emission.
      await container.read(cruxCxpRuntimeProvider.future);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());

      final controller = CxpOutboundEmitterController(container);
      addTearDown(controller.dispose);

      final received = <NotifySelection>[];
      final sub = boot.client.inbound.listen((m) {
        if (m.message is NotifySelection) {
          received.add(m.message as NotifySelection);
        }
      });

      container
          .read(selectedElementProvider.notifier)
          .select(
            const SelectedElement.cell(cellId: 'u_cpu'),
          );
      await waitFor(
        () => received.isNotEmpty,
        reason: 'the cell-selection NotifySelection never arrived',
      );
      container.read(selectedElementProvider.notifier).clear();
      // Negative assertion made deterministic: a follow-up selection
      // flows through the same controller → broadcast → socket pipeline
      // as any (suppressed) clear() emission, so once ITS message arrives
      // nothing can still be in flight ahead of it (same-socket FIFO).
      container
          .read(selectedElementProvider.notifier)
          .select(
            const SelectedElement.cell(cellId: 'u_dma'),
          );
      await waitFor(
        () => received.length >= 2,
        reason: 'the follow-up selection NotifySelection never arrived',
      );
      await sub.cancel();

      // Exactly the two cell selections arrived — the clear() emission
      // between them was suppressed.
      expect(received, hasLength(2));
      expect(received.first.elements.first.path, 'top.u_cpu');
      expect(received.last.elements.first.path, 'top.u_dma');
    });

    test(
      'does not broadcast when broadcastSelectionOnCrossProbe is off',
      () async {
        final boot = await _bootServerWithSubscribedClient();
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best effort */
          }
        });
        final container = ProviderContainer(
          overrides: [
            ..._cxpOverrides(boot.server),
            // Gate the emitter: the setting's default is ON; here it is OFF.
            cruxCxpSettingsProvider.overrideWith(_BroadcastOffSettings.new),
          ],
        );
        addTearDown(container.dispose);
        await container.read(cruxCxpRuntimeProvider.future);
        container.read(hierarchyTreeProvider.notifier).setModel(_model());

        final controller = CxpOutboundEmitterController(container);
        addTearDown(controller.dispose);

        final received = <NotifySelection>[];
        final sub = boot.client.inbound.listen((m) {
          if (m.message is NotifySelection) {
            received.add(m.message as NotifySelection);
          }
        });

        container
            .read(selectedElementProvider.notifier)
            .select(const SelectedElement.cell(cellId: 'u_cpu'));

        // Deterministic negative assertion: the barrier round-trip travels the
        // same FIFO socket a broadcast would, so once it completes any
        // (suppressed) emission would already have arrived.
        await cxpRoundTripBarrier(boot.client);
        await sub.cancel();

        expect(
          received,
          isEmpty,
          reason: 'auto-broadcast must be suppressed when the setting is off',
        );
      },
    );
  });
}

/// CXP settings with automatic selection broadcast turned OFF.
class _BroadcastOffSettings extends CruxCxpSettingsNotifier {
  @override
  CruxCxpSettings build() => const CruxCxpSettings(
    enabled: true,
    port: 54323,
    broadcastSelection: false,
  );
}

/// NetCrux's CXP binding over [rig]'s running runtime, as the app wires it.
List<Override> _cxpOverrides(CxpRuntimeRig rig) => <Override>[
  cruxCxpProductBindingProvider.overrideWithValue(kNetcruxCxpBinding),
  cruxCxpRuntimeProvider.overrideWith((ref) async => rig.runtime),
];
