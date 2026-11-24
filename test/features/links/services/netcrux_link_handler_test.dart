// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/links/services/netcrux_link_handler.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/workspace/providers/recent_lists.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';
import 'package:netcrux/services/links/netcrux_link.dart';
import 'package:netcrux/services/reload/source_file_watcher_provider.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/cxp_test_overrides.dart';
import '../../../helpers/telemetry_test_overrides.dart';
import '../../../helpers/workspace_app_harness.dart' show RowLayoutService;

/// The whole link flow over the real workspace, tab containers and netlist
/// reader: the confirmation is asked exactly when the file is new to the user
/// and its answer is not remembered, an open design's tab is focused rather
/// than duplicated, the cell or net is found by its hierarchical name in the
/// scope the name says and selected there, a scope over the layout limit opens
/// a Cone View, and every refusal opens nothing and asks nothing.
///
/// The design is `design_seed`: `top` holds `u_cpu` (a `cpu`, which holds
/// `pc_reg` and `u_alu`, an `alu` holding `xor0`) and `dma_reg`. A JSON netlist
/// is read in-process, and the Yosys probe fails the test if it is asked.
final String _seed = p.join(
  Directory.current.path,
  'test',
  'fixtures',
  'netlist',
  'design_seed',
  'generated',
  'design_seed.netlist.json',
);

class _Settings extends AppSettingsNotifier {
  _Settings(this.limit);

  final int limit;

  @override
  Future<AppSettings> build() async =>
      const AppSettings.defaults().copyWith(layoutCellLimit: limit);
}

class _Harness {
  _Harness(this.root, this.tabs, this.dir);

  final ProviderContainer root;
  final TabContainerManager tabs;
  final Directory dir;
  final List<String> asked = [];
  final List<ProviderContainer> framed = [];
  bool answer = true;

  Future<bool> confirm(String path) async {
    asked.add(path);
    return answer;
  }

  Future<NetCruxLinkOutcome> open(String raw) => openNetCruxLink(
    root,
    raw,
    confirm: confirm,
    frame: framed.add,
    tabs: tabs,
  );

  List<WorkspaceTab<NetcruxTabPayload>> get openTabs =>
      root.read(netcruxWorkspaceProvider).value?.tabs ?? const [];

  int get tabCount => openTabs.length;

  ProviderContainer activeTab() {
    final id = root.read(netcruxWorkspaceProvider).value?.activeTabId;
    expect(id, isNotNull, reason: 'a tab must be open');
    return tabs.containerFor(id!);
  }

  /// A copy of the seed design in the harness's own folder, so each test
  /// starts with a file the user has never opened.
  String copy([String name = 'design.json']) {
    final path = p.join(dir.path, name);
    File(_seed).copySync(path);
    return path;
  }
}

Future<_Harness> _harness({int layoutLimit = 0}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dir = Directory(
    Directory.systemTemp
        .createTempSync('netcrux_link_handler_')
        .resolveSymbolicLinksSync(),
  );
  final root = ProviderContainer(
    overrides: [
      ...netcruxTelemetryTestOverrides(),
      ...netcruxCxpOffTestOverrides(),
      settingsServiceProvider.overrideWithValue(
        SettingsService<AppSettings>(
          const NetcruxSettingsCodec(),
          prefsOverride: prefs,
        ),
      ),
      appSettingsProvider.overrideWith(() => _Settings(layoutLimit)),
      netcruxWorkspaceProvider.overrideWith(
        () => NetcruxWorkspaceNotifier(
          service: WorkspaceService<NetcruxTabPayload>(
            codec: const NetcruxWorkspaceCodec(),
            directoryFactory: () async =>
                Directory(p.join(dir.path, 'workspace'))
                  ..createSync(recursive: true),
            logger: (_) {},
          ),
          autoSaveDebounce: const Duration(milliseconds: 10),
          restoreGate: () async => false,
        ),
      ),
      yosysAvailabilityProvider.overrideWith(
        (ref) async => fail('a link to a netlist must not probe for Yosys'),
      ),
      sourceFilePollIntervalProvider.overrideWithValue(null),
      elkLayoutServiceProvider.overrideWithValue(RowLayoutService()),
    ],
  );
  final tabs = TabContainerManager(
    rootContainer: root,
    overridesFactory: netcruxTabOverridesFactory,
  );
  root.read(netcruxWorkspaceProvider.notifier).addScopeReconciler(tabs);
  await root.read(appSettingsProvider.future);
  await root.read(netcruxWorkspaceProvider.future);
  addTearDown(() async {
    // Lets the debounced workspace save land before its folder goes.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    tabs.dispose();
    root.dispose();
    dir.deleteSync(recursive: true);
  });
  return _Harness(root, tabs, dir);
}

String _link(String file, {String? cell, String? net}) {
  final query = [
    'file=${Uri.encodeComponent(file)}',
    if (cell != null) 'cell=${Uri.encodeComponent(cell)}',
    if (net != null) 'net=${Uri.encodeComponent(net)}',
  ].join('&');
  return 'netcrux://open?$query';
}

List<String>? _scope(ProviderContainer tab) =>
    tab.read(hierarchyTreeProvider).selected?.path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the confirmation', () {
    test('a file the user has not opened is confirmed first, by its resolved '
        'path', () async {
      final h = await _harness();
      final path = h.copy();
      final outcome = await h.open(_link(path));
      expect(h.asked, [path]);
      expect(outcome.opened, isTrue);
      expect(outcome.openedTab, isTrue);
      expect(h.tabCount, 1);
      final model = h.activeTab().read(loadedNetlistProvider).value;
      expect(model?.topModule?.name, 'top');
    });

    test('declining opens nothing', () async {
      final h = await _harness();
      final path = h.copy();
      h.answer = false;
      final outcome = await h.open(_link(path, cell: 'top.dma_reg'));
      expect(outcome.declined, isTrue);
      expect(outcome.opened, isFalse);
      expect(h.tabCount, 0);
      expect(h.framed, isEmpty);
    });

    test('a confirmation that throws counts as Cancel', () async {
      final h = await _harness();
      final path = h.copy();
      final outcome = await openNetCruxLink(
        h.root,
        _link(path),
        confirm: (_) async => throw StateError('no screen'),
        tabs: h.tabs,
      );
      expect(outcome.declined, isTrue);
      expect(h.tabCount, 0);
    });

    test('a design open in a tab is focused without asking, never '
        'duplicated', () async {
      final h = await _harness();
      final path = h.copy();
      await h.open(_link(path));
      final other = h.copy('other.json');
      await h.open(_link(other));
      expect(h.tabCount, 2);
      h.asked.clear();

      final outcome = await h.open(_link(path, cell: 'top.dma_reg'));
      expect(h.asked, isEmpty);
      expect(outcome.openedTab, isFalse);
      expect(h.tabCount, 2);
      final active = h.openTabs.singleWhere(
        (t) => t.id == h.root.read(netcruxWorkspaceProvider).value?.activeTabId,
      );
      expect(active.payload.sourceFiles, [path]);
    });

    test('a file in Recent Files opens without asking', () async {
      final h = await _harness();
      final path = h.copy();
      h.root.read(recentSources.provider.notifier).markOpened(path);
      final outcome = await h.open(_link(path));
      expect(h.asked, isEmpty);
      expect(outcome.opened, isTrue);
    });

    test('consent is not remembered: closing the tab asks again', () async {
      final h = await _harness();
      final path = h.copy();
      await h.open(_link(path));
      expect(h.asked, hasLength(1));
      expect(
        h.root.read(recentSources.provider),
        isNot(contains(path)),
        reason: 'a link open must not quietly add the file to Recent Files',
      );
      expect(h.root.read(recentProjects.provider), isNot(contains(path)));
      final tabId = h.root.read(netcruxWorkspaceProvider).value!.activeTabId!;
      await h.root.read(netcruxWorkspaceProvider.notifier).closeTab(tabId);
      expect(h.tabCount, 0);

      await h.open(_link(path));
      expect(h.asked, hasLength(2));
    });

    test('a file swapped while the question was up is not opened', () async {
      final h = await _harness();
      final path = h.copy();
      final outcome = await openNetCruxLink(
        h.root,
        _link(path),
        confirm: (asked) async {
          File(asked).deleteSync();
          return true;
        },
        tabs: h.tabs,
      );
      expect(outcome.failure, NetCruxLinkFailure.fileNotFound);
      expect(h.tabCount, 0);
    });
  });

  group('refusals open nothing and ask nothing', () {
    test('a malformed link', () async {
      final h = await _harness();
      final outcome = await h.open('netcrux://run?file=/x.json');
      expect(outcome.failure, NetCruxLinkFailure.malformed);
      expect(outcome.parseRefusal, NetCruxLinkRefusal.malformed);
      expect(h.asked, isEmpty);
      expect(h.tabCount, 0);
    });

    test('a relative path', () async {
      final h = await _harness();
      final outcome = await h.open('netcrux://open?file=rtl/top.json');
      expect(outcome.failure, NetCruxLinkFailure.pathRefused);
      expect(outcome.parseRefusal, NetCruxLinkRefusal.relativePath);
      expect(h.asked, isEmpty);
      expect(h.tabCount, 0);
    });

    test('a missing file names the file', () async {
      final h = await _harness();
      final outcome = await h.open(_link(p.join(h.dir.path, 'gone.json')));
      expect(outcome.failure, NetCruxLinkFailure.fileNotFound);
      expect(outcome.fileName, 'gone.json');
      expect(h.asked, isEmpty);
      expect(h.tabCount, 0);
    });

    test('a project file, which carries Yosys commands, is not a design a '
        'link opens', () async {
      final h = await _harness();
      final project = p.join(h.dir.path, 'design.netcrux-project');
      File(project).writeAsStringSync('{"version": 1}');
      final outcome = await h.open(_link(project));
      expect(outcome.failure, NetCruxLinkFailure.notADesign);
      expect(outcome.fileName, 'design.netcrux-project');
      expect(h.asked, isEmpty);
      expect(h.tabCount, 0);
    });

    test('a netlist that does not read says so', () async {
      final h = await _harness();
      final broken = p.join(h.dir.path, 'broken.json');
      File(broken).writeAsStringSync('{"modules": ');
      final outcome = await h.open(_link(broken, cell: 'top.u'));
      expect(outcome.failure, NetCruxLinkFailure.loadFailed);
      expect(outcome.fileName, 'broken.json');
      expect(h.framed, isEmpty);
    });
  });

  group('cell and net', () {
    test(
      'a rooted cell name shows its scope, selects it and frames it',
      () async {
        final h = await _harness();
        final path = h.copy();
        final outcome = await h.open(_link(path, cell: 'top.u_cpu.pc_reg'));
        expect(outcome.elementNotFound, isFalse);
        expect(outcome.kind, NetCruxLinkElementKind.cell);
        expect(outcome.coneView, isFalse);
        final tab = h.activeTab();
        expect(_scope(tab), ['u_cpu']);
        expect(
          tab.read(selectedElementProvider).primary,
          const SelectedElement.cell(cellId: 'pc_reg'),
        );
        expect(tab.read(revealRequestProvider), 'pc_reg');
        expect(h.framed, [tab]);
        expect(tab.read(coneViewProvider), isNull);
      },
    );

    test('a name written from below the top is found the same way', () async {
      final h = await _harness();
      final path = h.copy();
      await h.open(_link(path, cell: 'u_cpu.u_alu.xor0'));
      final tab = h.activeTab();
      expect(_scope(tab), ['u_cpu', 'u_alu']);
      expect(
        tab.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'xor0'),
      );
    });

    test('a net is selected in its scope; a bit select names the whole '
        'net', () async {
      final h = await _harness();
      final path = h.copy();
      final outcome = await h.open(_link(path, net: 'top.u_cpu.alu_y'));
      expect(outcome.elementNotFound, isFalse);
      expect(outcome.kind, NetCruxLinkElementKind.net);
      final tab = h.activeTab();
      expect(_scope(tab), ['u_cpu']);
      expect(tab.read(selectedElementProvider).isNotEmpty, isTrue);
      expect(h.framed, [tab]);

      final bit = await h.open(_link(path, net: 'u_cpu.alu_y[0]'));
      expect(bit.elementNotFound, isFalse);
    });

    test('an unknown name opens the design and says so, selecting '
        'nothing', () async {
      final h = await _harness();
      final path = h.copy();
      final outcome = await h.open(_link(path, cell: 'top.u_cpu.nope'));
      expect(outcome.opened, isTrue);
      expect(outcome.elementNotFound, isTrue);
      expect(outcome.name, 'top.u_cpu.nope');
      expect(h.activeTab().read(selectedElementProvider).isEmpty, isTrue);
      expect(h.framed, isEmpty);
    });

    test('a cell is not found as a net, nor a net as a cell', () async {
      final h = await _harness();
      final path = h.copy();
      final asNet = await h.open(_link(path, net: 'top.u_cpu.pc_reg'));
      expect(asNet.elementNotFound, isTrue);
      final asCell = await h.open(_link(path, cell: 'top.u_cpu.alu_y'));
      expect(asCell.elementNotFound, isTrue);
    });

    test('a leaf alone is never matched in some other scope', () async {
      final h = await _harness();
      final path = h.copy();
      final outcome = await h.open(_link(path, cell: 'xor0'));
      expect(outcome.elementNotFound, isTrue);
    });

    test('a scope over the layout limit shows the element in a Cone '
        'View', () async {
      final h = await _harness(layoutLimit: 1);
      final path = h.copy();
      final outcome = await h.open(_link(path, cell: 'top.dma_reg'));
      expect(outcome.coneView, isTrue);
      final tab = h.activeTab();
      final cone = tab.read(coneViewProvider);
      expect(cone, isNotNull);
      expect(cone!.root, const SelectedElement.cell(cellId: 'dma_reg'));
      expect(cone.scope.path, isEmpty);
      expect(h.framed, [tab]);
    });

    test('under the limit no cone opens', () async {
      final h = await _harness(layoutLimit: 100);
      final path = h.copy();
      final outcome = await h.open(_link(path, cell: 'top.dma_reg'));
      expect(outcome.coneView, isFalse);
      expect(h.activeTab().read(coneViewProvider), isNull);
    });
  });

  group('inbox', () {
    test('holds links until ready, then handles them in turn', () async {
      final handled = <String>[];
      final inbox = NetCruxLinkInbox((raw) async => handled.add(raw))..add('a');
      await Future<void>.delayed(Duration.zero);
      expect(handled, isEmpty);
      inbox.markReady();
      await Future<void>.delayed(Duration.zero);
      expect(handled, ['a']);
    });

    test('keeps only the newest link while one is in progress', () async {
      final handled = <String>[];
      final gate = Completer<void>();
      NetCruxLinkInbox((raw) async {
          handled.add(raw);
          if (raw == 'first') await gate.future;
        })
        ..markReady()
        ..add('first')
        ..add('second')
        ..add('third')
        ..add('fourth');
      await Future<void>.delayed(Duration.zero);
      expect(handled, ['first']);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(handled, ['first', 'fourth']);
    });

    test('a handler that throws does not stop the next link', () async {
      final handled = <String>[];
      final inbox =
          NetCruxLinkInbox((raw) async {
              handled.add(raw);
              throw StateError('boom');
            })
            ..markReady()
            ..add('a');
      await Future<void>.delayed(Duration.zero);
      inbox.add('b');
      await Future<void>.delayed(Duration.zero);
      expect(handled, ['a', 'b']);
    });
  });
}
