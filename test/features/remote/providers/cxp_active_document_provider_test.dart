// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/remote/providers/cxp_active_document_provider.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

import '../../../helpers/telemetry_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late CruxCxpRuntime runtime;
  late ProviderContainer root;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('nc_active_doc_');
    // A runtime that is never started: it keeps the announced design, which
    // is what the sync is responsible for (CXP §8.1; the shared package
    // tests the manifest rewrite itself).
    runtime = CruxCxpRuntime(
      binding: kNetcruxCxpBinding,
      productVersion: '0.0.0-test',
      manifestDirectory: '${tmp.path}/peers',
      port: 0,
      handler: () => const CruxCxpRequestHandler(),
    );
    root = ProviderContainer(
      overrides: <Override>[
        ...netcruxTelemetryTestOverrides(),
        cruxCxpRuntimeProvider.overrideWith((ref) async => runtime),
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(
            service: WorkspaceService<NetcruxTabPayload>(
              codec: const NetcruxWorkspaceCodec(),
              directoryFactory: () async =>
                  Directory('${tmp.path}/ws')..createSync(recursive: true),
              logger: (_) {},
            ),
          ),
        ),
      ],
    );
    await root.read(netcruxWorkspaceProvider.future);
    await root.read(cruxCxpRuntimeProvider.future);
  });

  tearDown(() async {
    root.dispose();
    await runtime.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('the runtime announces the active tab and follows it', () async {
    final sub = root.listen(cxpActiveDocumentSyncProvider, (_, _) {});
    addTearDown(sub.close);
    final notifier = root.read(netcruxWorkspaceProvider.notifier);

    await settle();
    expect(runtime.activeDocument, isNull, reason: 'no tab, no design');

    final alu = await notifier.openTab(
      displayName: 'alu.v',
      payload: const NetcruxTabPayload(sourceFiles: <String>['/w/rtl/alu.v']),
    );
    await settle();
    expect(runtime.activeDocument, 'alu.v');

    await notifier.openTab(
      displayName: '/w/rtl/fifo.sv',
      payload: const NetcruxTabPayload(sourceFiles: <String>['/w/rtl/fifo.sv']),
    );
    await settle();
    expect(runtime.activeDocument, 'fifo.sv', reason: 'a name, never a path');

    await notifier.setActiveTab(alu);
    await settle();
    expect(runtime.activeDocument, 'alu.v');
  });

  test('an empty tab announces no design', () async {
    final sub = root.listen(cxpActiveDocumentSyncProvider, (_, _) {});
    addTearDown(sub.close);
    await root
        .read(netcruxWorkspaceProvider.notifier)
        .openTab(displayName: 'Untitled', payload: NetcruxTabPayload.empty);
    await settle();
    expect(root.read(cxpActiveDocumentProvider), isNull);
    expect(runtime.activeDocument, isNull);
  });
}
