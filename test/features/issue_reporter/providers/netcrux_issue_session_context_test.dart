// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/issue_reporter/providers/netcrux_issue_session_context.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_runner_provider.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// NetCrux's contribution to the shared beta issue reporter.
///
/// The headline test here is the **privacy contract**: a Session State body
/// rendered from the real contributor, against a realistically populated
/// session (a design loaded from a real on-disk path, a Yosys binary at a real
/// path, a selection on a named cell), must contain no filesystem path and no
/// identifier lifted from the user's own RTL. `crux_issue_reporter` asserts
/// the same thing over a synthetic contributor; the package cannot see what a
/// product chooses to put in a `CruxIssueField`, so the assertion is repeated
/// here where it can.

/// Source paths deliberately chosen to be recognisable if they leak.
const _sourceDir = '/Users/somebody/Projects/secret-asic/rtl';
const _sourceFiles = <String>[
  '$_sourceDir/cpu_top.v',
  '$_sourceDir/alu.sv',
  '$_sourceDir/fifo.vhd',
];
const _yosysPath = '/opt/homebrew/bin/yosys';

/// A design whose module / cell / net names would identify the user's IP.
final _model = NetlistModel(
  creator: 'Yosys 0.50 (git sha1 deadbeef)',
  modules: {
    'cpu_top': Module(
      name: 'cpu_top',
      attributes: const {'top': '00000000000000000000000000000001'},
      ports: const {},
      cells: {
        for (final name in ['u_alu', 'u_fifo', 'u_regfile'])
          name: Cell(
            name: name,
            type: r'$dff',
            parameters: const {},
            attributes: const {},
            portDirections: const {},
            connections: const {},
          ),
      },
      nets: {
        for (final name in ['clk', 'rst_n', 'secret_key_bus'])
          name: Net(name: name, bits: const [], attributes: const {}),
      },
    ),
    'alu': const Module(
      name: 'alu',
      attributes: {},
      ports: {},
      cells: {
        'u_add': Cell(
          name: 'u_add',
          type: r'$add',
          parameters: {},
          attributes: {},
          portDirections: {},
          connections: {},
        ),
      },
      nets: {},
    ),
  },
);

/// Returns [_model] as canned `write_json` output so the real elaboration
/// pipeline runs end-to-end without spawning a Yosys subprocess.
class _SeededRunner extends YosysRunner {
  _SeededRunner(this.rawJson);

  final String rawJson;

  @override
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(String line)? onStderrLine,
  }) async => YosysRunSuccess(rawJson: rawJson, stdout: '', stderr: '');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer root;
  late TabContainerManager manager;

  /// Boots a root container with the session contributor bound, a per-tab
  /// container manager, and (optionally) a seeded design in the active tab.
  Future<void> bootHarness({
    bool elaborate = false,
    bool openTab = true,
  }) async {
    root = ProviderContainer(
      overrides: <Override>[
        ...netcruxTelemetryTestOverrides(),
        netcruxIssueSessionContextOverride,
        // A real probe would shell out to `yosys -V`.
        yosysAvailabilityProvider.overrideWith(
          (_) async => const YosysAvailability.available(
            executablePath: _yosysPath,
            versionString: 'Yosys 0.50 (git sha1 deadbeef)',
          ),
        ),
        yosysRunnerProvider.overrideWith(
          (_) => _SeededRunner(jsonEncode(_model.toJson())),
        ),
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(
            service: WorkspaceService<NetcruxTabPayload>(
              codec: const NetcruxWorkspaceCodec(),
              directoryFactory: () async =>
                  Directory.systemTemp.createTempSync('netcrux_issue_test_'),
              logger: (_) {},
            ),
          ),
        ),
      ],
    );
    addTearDown(root.dispose);

    manager = TabContainerManager(
      rootContainer: root,
      overridesFactory: netcruxTabOverridesFactory,
    );
    addTearDown(manager.dispose);
    root.read(tabContainerManagerHolderProvider).manager = manager;
    await root.read(netcruxWorkspaceProvider.future);
    await root.read(yosysAvailabilityProvider.future);

    if (!openTab) return;
    final tabId = await root
        .read(netcruxWorkspaceProvider.notifier)
        .openTab(displayName: 'cpu_top', payload: NetcruxTabPayload.empty);
    await root.read(netcruxWorkspaceProvider.future);

    final tab = manager.containerFor(tabId);
    tab.read(currentProjectProvider.notifier).setSourceFiles(_sourceFiles);
    if (!elaborate) return;
    // Drives the real pipeline: availability probe → seeded runner →
    // isolate parse. Nothing here shells out.
    await tab.read(loadedNetlistProvider.future);
    tab
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'u_alu'));
  }

  /// Renders the Session State markdown the way the reporter would.
  String renderSessionBody(CruxIssueSessionContext context) =>
      const CruxIssueReporterService(
            config: CruxIssueReporterConfig(
              productName: 'NetCrux',
              repositorySlug: 'Ferrite-Engineering/netcrux',
            ),
          )
          .buildSessionCategory(title: 'Session State', context: context)
          .markdownBody;

  group('buildNetcruxIssueSessionContext', () {
    test(
      'PRIVACY: a Session State body carries no file paths',
      () async {
        await bootHarness(elaborate: true);
        final body = renderSessionBody(
          root.read(cruxIssueSessionContextProvider),
        );

        // The contract, stated the same way `crux_issue_reporter`'s own suite
        // states it: no path separator of either flavour survives into the
        // body a user is about to publish on GitHub.
        expect(body, isNot(contains('/')));
        expect(body, isNot(contains(r'\')));

        // And spelled out for the specific things this session held.
        for (final leak in <String>[
          ..._sourceFiles,
          _sourceDir,
          _yosysPath,
          'cpu_top.v',
          'alu.sv',
          'fifo.vhd',
          // Identifiers lifted from the user's RTL are private too.
          'u_alu',
          'secret_key_bus',
          'regfile',
        ]) {
          expect(
            body,
            isNot(contains(leak)),
            reason: '"$leak" leaked into a public issue body',
          );
        }
      },
    );

    test('PRIVACY: the attribute map carries no paths either', () async {
      await bootHarness(elaborate: true);
      final attributes = root
          .read(cruxIssueSessionContextProvider)
          .attributes
          .toString();
      expect(attributes, isNot(contains('/')));
      expect(attributes, isNot(contains(r'\')));
    });

    test('reports the counts a maintainer needs to triage', () async {
      await bootHarness(elaborate: true);
      final body = renderSessionBody(
        root.read(cruxIssueSessionContextProvider),
      );

      expect(body, contains('- **Open tabs:** 1'));
      expect(body, contains('- **Panes:** 1'));
      expect(body, contains('- **Source files (active tab):** 3'));
      expect(body, contains('- **Elaboration:** succeeded'));
      expect(body, contains('- **Modules:** 2'));
      // 3 cells in cpu_top + 1 in alu.
      expect(body, contains('- **Cells:** 4'));
      expect(body, contains('- **Nets:** 3'));
      expect(body, contains('- **Yosys:** available'));
      expect(body, contains('- **Selection:** yes'));
    });

    test('reports source languages by name, never by path', () async {
      await bootHarness(elaborate: true);
      final body = renderSessionBody(
        root.read(cruxIssueSessionContextProvider),
      );
      // A format/language name is metadata, not user content — the same
      // reasoning that lets the WaveCrux contributor report "VCD".
      expect(body, contains('systemVerilog'));
      expect(body, contains('verilog'));
      expect(body, contains('vhdl'));
    });

    test('an empty workspace still produces a usable snapshot', () async {
      await bootHarness(openTab: false);
      final context = root.read(cruxIssueSessionContextProvider);
      final body = renderSessionBody(context);

      expect(context.isNotEmpty, isTrue);
      expect(body, contains('- **Open tabs:** 0'));
      expect(body, contains('- **Elaboration:** no design'));
      expect(body, contains('- **Modules:** 0'));
      expect(body, isNot(contains('/')));
    });

    test('an elaboration still running reports "in progress"', () async {
      // Source files bound, pipeline not yet awaited — the snapshot must
      // describe the transient state rather than claim a design is loaded.
      await bootHarness();
      final body = renderSessionBody(
        root.read(cruxIssueSessionContextProvider),
      );
      expect(body, contains('- **Source files (active tab):** 3'));
      expect(body, contains('- **Elaboration:** in progress'));
      expect(body, contains('- **Modules:** 0'));
    });

    test('publishes attributes for the Pro overlay seam', () async {
      await bootHarness(elaborate: true);
      final attributes = root.read(cruxIssueSessionContextProvider).attributes;

      expect(attributes[kNetcruxIssueAttrOpenTabs], 1);
      expect(attributes[kNetcruxIssueAttrModuleCount], 2);
      expect(attributes[kNetcruxIssueAttrCellCount], 4);
      // Fixed vocabulary, never a user-supplied name — this is what the
      // overlay's "Pro State" category is built from.
      expect(attributes[kNetcruxIssueAttrActiveProSurfaces], isEmpty);
    });

    test(
      'resolves through the chrome ProviderScope with real counts',
      () async {
        // `NetcruxApp` mounts a nested `ProviderScope` inside
        // `MaterialApp.builder` to supply the localized string bundles, and
        // `CruxIssueReporterDialog.openAdaptive` resolves (and invalidates)
        // the session provider through *that* container. NetCrux keeps a
        // single root container and publishes the tab manager into a
        // root-scope mutable holder, so the contributor materializes at root
        // and the nested scope sees the same instance — but a regression that
        // moved it into the child scope would silently report all-zero counts
        // (the defensive fallbacks swallow a failed per-tab lookup). Asserting
        // NON-ZERO counts through the child container is what catches that;
        // the privacy assertions above would pass just as happily on zeros.
        await bootHarness(elaborate: true);
        final chromeScope = ProviderContainer(parent: root);
        addTearDown(chromeScope.dispose);

        chromeScope.invalidate(cruxIssueSessionContextProvider);
        final body = renderSessionBody(
          chromeScope.read(cruxIssueSessionContextProvider),
        );

        expect(body, contains('- **Open tabs:** 1'));
        expect(body, contains('- **Modules:** 2'));
        expect(body, contains('- **Cells:** 4'));
        expect(body, contains('- **Nets:** 3'));
        expect(body, isNot(contains('- **Modules:** 0')));
      },
    );

    test('degrades to an empty-workspace snapshot with no tab manager', () {
      // A bare unit-test container never ran `bootstrap`, so the holder has no
      // manager. Building the reporter must not throw.
      final bare = ProviderContainer(
        overrides: <Override>[
          ...netcruxTelemetryTestOverrides(),
          netcruxIssueSessionContextOverride,
        ],
      );
      addTearDown(bare.dispose);
      expect(
        () => bare.read(cruxIssueSessionContextProvider),
        returnsNormally,
      );
    });
  });
}
