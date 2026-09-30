// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/hierarchy/providers/scope_flash_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/remote/cxp/cxp_inbound_handler.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:netcrux/services/remote/cxp/editor_open_service.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// [posix] spelled as an absolute path on the host.
///
/// On Windows a path with no drive (`/abs/path`) is rooted but not absolute,
/// and the CXP floor refuses it (a receiver cannot know which drive was
/// meant), so a fixture that must pass the floor names a drive there. Roots
/// and requests both go through here, so they stay spelled alike.
String _abs(String posix) =>
    Platform.isWindows ? 'C:${posix.replaceAll('/', r'\')}' : posix;

/// The reset-domain design used by the yosys-gated B→A integration test, a
/// copy of the EDACrux scenario design kept in this repo's fixtures.
const String _resetDomainsVPath = 'test/fixtures/verilog/reset_domains.v';

NetlistModel _model() {
  Cell cell(
    String name,
    String type, {
    Map<String, PortDirection> portDirections = const {},
    Map<String, List<BitRef>> connections = const {},
  }) => Cell(
    name: name,
    type: type,
    parameters: const {},
    attributes: const {},
    portDirections: portDirections,
    connections: connections,
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
      // u_cpu carries a real CLK pin so cross-probe existence checks can
      // distinguish a present port from a syntactically-valid-but-absent
      // one.
      'u_cpu': cell(
        'u_cpu',
        'cpu',
        portDirections: const {'CLK': PortDirection.input},
        connections: const {
          'CLK': <BitRef>[NetBit(1)],
        },
      ),
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

/// A single-scope model whose top module declares a NAMED net (`data`,
/// net id 7) with both a driver (a flop's Q) and a sink (the module
/// output port), so the net has a rendered schematic edge. Used to
/// exercise the inbound net-highlight path, which must recover the net's
/// real net id from the live netlist.
NetlistModel _modelWithNet() {
  const top = Module(
    name: 'top',
    attributes: <String, String>{'top': '1'},
    ports: <String, Port>{
      'q': Port(
        name: 'q',
        direction: PortDirection.output,
        bits: <BitRef>[NetBit(7)],
      ),
    },
    cells: <String, Cell>{
      'u_ff': Cell(
        name: 'u_ff',
        type: r'$dff',
        parameters: <String, String>{},
        attributes: <String, String>{},
        portDirections: <String, PortDirection>{'Q': PortDirection.output},
        connections: <String, List<BitRef>>{
          'Q': <BitRef>[NetBit(7)],
        },
      ),
    },
    nets: <String, Net>{
      'data': Net(
        name: 'data',
        bits: <BitRef>[NetBit(7)],
        attributes: <String, String>{},
      ),
    },
  );
  return const NetlistModel(
    creator: 'test',
    modules: <String, Module>{'top': top},
  );
}

Future<
  ({
    NetcruxCxpServer server,
    LocalCxpClient client,
    ProviderContainer rootContainer,
    ProviderContainer tabContainer,
    Directory tmp,
  })
>
_setup({
  NetlistModel? model,
  bool loadModel = true,
  List<Override> rootOverrides = const <Override>[],
  List<String>? openDirectories,
}) async {
  final tmp = Directory.systemTemp.createTempSync('cxp_inbound_');
  // CXP §11's containment rule over a fixed root set. The production
  // callback reads the source files of every open tab; this harness loads a
  // netlist model directly and never opens a project, so it would report
  // nothing open and every peer-supplied path would be refused. As in
  // production, the rooted rule goes to the root container, where the handler
  // reads it for the value it is about to open, and the server screens the
  // wire with the floor (`kCxpOpenArtifactContainment` says why).
  final roots = openDirectories ?? <String>[_abs('/abs/path')];
  final containment = CxpPathContainment(roots: () => roots);
  final server = NetcruxCxpServer(
    productVersion: '0.0.0-test',
    manifestDirectory: '${tmp.path}/peers',
    containment: kCxpOpenArtifactContainment,
  );
  await server.start();

  final client = LocalCxpClient(
    selfIdentity: const PeerIdentity(
      peerId: 'wavecrux-inbound-test',
      productName: 'wavecrux',
      productVersion: '0.0.0-test',
    ),
  );
  await client.connect(
    host: '127.0.0.1',
    port: server.boundPort!,
    token: cxpProcessAuthToken,
  );

  // Build a root + per-tab container shaped like production.
  final rootContainer = ProviderContainer(
    overrides: <Override>[
      ...netcruxTelemetryTestOverrides(),
      cxpPathContainmentProvider.overrideWithValue(containment),
      ...rootOverrides,
    ],
  );
  final tabContainer = ProviderContainer(parent: rootContainer);
  if (loadModel) {
    tabContainer
        .read(hierarchyTreeProvider.notifier)
        .setModel(model ?? _model());
  }

  return (
    server: server,
    client: client,
    rootContainer: rootContainer,
    tabContainer: tabContainer,
    tmp: tmp,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // appSettingsProvider depends on SharedPreferences via SettingsService.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('CxpInboundHandler', () {
    test('request_highlight on an instance selects the cell', () async {
      final boot = await _setup();
      addTearDown(() async {
        await boot.client.dispose();
        await boot.server.stop();
        boot.tabContainer.dispose();
        boot.rootContainer.dispose();
        try {
          boot.tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* best */
        }
      });

      final handler = CxpInboundHandler(
        server: boot.server.server!,
        rootContainer: boot.rootContainer,
        activeTabContainerLookup: () => boot.tabContainer,
      );
      addTearDown(handler.dispose);

      final ackFuture = boot.client.inbound.firstWhere(
        (m) => m.message is RequestHighlightAck,
      );
      boot.client.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.instance,
            path: 'top.u_cpu:cell',
          ),
        ),
      );
      final inbound = await ackFuture.timeout(const Duration(seconds: 2));
      final ack = inbound.message as RequestHighlightAck;
      expect(ack.honored, isTrue);

      final selection = boot.tabContainer.read(selectedElementProvider);
      expect(selection.primary, isA<SelectedElementCell>());
      expect(
        (selection.primary as SelectedElementCell).cellId,
        'u_cpu',
      );
    });

    test(
      'request_highlight with an unrecognized kind is ignored, not fatal',
      () async {
        // `ElementKind` is an open value type, so a peer on a newer
        // protocol revision can name a kind this build does not model.
        // The handler must decline it gracefully — an ack with
        // honored:false and a reason — and leave the tab's selection
        // untouched. Throwing or crashing here would take down the CXP
        // link over a message the protocol explicitly permits.
        final boot = await _setup();
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
        );
        addTearDown(handler.dispose);

        final before = boot.tabContainer.read(selectedElementProvider);

        final ackFuture = boot.client.inbound.firstWhere(
          (m) => m.message is RequestHighlightAck,
        );
        boot.client.send(
          RequestHighlight(
            element: ElementId(
              kind: ElementKind('quantum_flux_capacitor'),
              path: 'top.u_cpu',
            ),
          ),
        );
        final inbound = await ackFuture.timeout(const Duration(seconds: 2));
        final ack = inbound.message as RequestHighlightAck;
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('quantum_flux_capacitor'));

        // Selection is unchanged and the link is still usable.
        expect(
          boot.tabContainer.read(selectedElementProvider).primary,
          before.primary,
        );
      },
    );

    test('request_highlight on a port selects the port', () async {
      final boot = await _setup();
      addTearDown(() async {
        await boot.client.dispose();
        await boot.server.stop();
        boot.tabContainer.dispose();
        boot.rootContainer.dispose();
        try {
          boot.tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* best */
        }
      });
      final handler = CxpInboundHandler(
        server: boot.server.server!,
        rootContainer: boot.rootContainer,
        activeTabContainerLookup: () => boot.tabContainer,
      );
      addTearDown(handler.dispose);

      final ackFuture = boot.client.inbound.firstWhere(
        (m) => m.message is RequestHighlightAck,
      );
      boot.client.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.port,
            path: 'top.u_cpu.CLK',
          ),
        ),
      );
      final inbound = await ackFuture.timeout(const Duration(seconds: 2));
      expect((inbound.message as RequestHighlightAck).honored, isTrue);

      final selection = boot.tabContainer.read(selectedElementProvider);
      expect(selection.primary, isA<SelectedElementPort>());
      expect(
        (selection.primary as SelectedElementPort).portName,
        'CLK',
      );
    });

    test(
      'request_highlight on a named net selects a wire carrying the '
      'real net id (not the netId:0 placeholder that never highlighted)',
      () async {
        final boot = await _setup(model: _modelWithNet());
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
        );
        addTearDown(handler.dispose);

        final ackFuture = boot.client.inbound.firstWhere(
          (m) => m.message is RequestHighlightAck,
        );
        boot.client.send(
          const RequestHighlight(
            element: ElementId(kind: ElementKind.net, path: 'top.data'),
          ),
        );
        final inbound = await ackFuture.timeout(const Duration(seconds: 2));
        expect((inbound.message as RequestHighlightAck).honored, isTrue);

        final selection = boot.tabContainer.read(selectedElementProvider);
        expect(selection.primary, isA<SelectedElementWire>());
        // The renderer highlights a wire by net id, so the recovered net
        // id must be the real one (7) — the old code emitted 0 and the
        // highlight silently missed.
        expect((selection.primary as SelectedElementWire).netId, 7);
      },
    );

    test(
      'request_highlight on a nonexistent net acks honored=false',
      () async {
        final boot = await _setup(model: _modelWithNet());
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
        );
        addTearDown(handler.dispose);

        final before = boot.tabContainer.read(selectedElementProvider);
        final ackFuture = boot.client.inbound.firstWhere(
          (m) => m.message is RequestHighlightAck,
        );
        boot.client.send(
          const RequestHighlight(
            element: ElementId(kind: ElementKind.net, path: 'top.nope'),
          ),
        );
        final inbound = await ackFuture.timeout(const Duration(seconds: 2));
        expect((inbound.message as RequestHighlightAck).honored, isFalse);
        expect(
          boot.tabContainer.read(selectedElementProvider).primary,
          before.primary,
        );
      },
    );

    test(
      'request_highlight on a nonexistent instance acks honored=false and '
      'leaves selection untouched',
      () async {
        final boot = await _setup();
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
        );
        addTearDown(handler.dispose);

        final before = boot.tabContainer.read(selectedElementProvider);
        final ackFuture = boot.client.inbound.firstWhere(
          (m) => m.message is RequestHighlightAck,
        );
        boot.client.send(
          const RequestHighlight(
            element: ElementId(
              kind: ElementKind.instance,
              path: 'top.nonexistent_cell:cell',
            ),
          ),
        );
        final inbound = await ackFuture.timeout(const Duration(seconds: 2));
        final ack = inbound.message as RequestHighlightAck;
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('not found'));
        expect(
          boot.tabContainer.read(selectedElementProvider).primary,
          before.primary,
        );
      },
    );

    test(
      'request_highlight on an absent port of a present cell acks '
      'honored=false',
      () async {
        final boot = await _setup();
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
        );
        addTearDown(handler.dispose);

        final ackFuture = boot.client.inbound.firstWhere(
          (m) => m.message is RequestHighlightAck,
        );
        // u_cpu exists but carries no RST pin.
        boot.client.send(
          const RequestHighlight(
            element: ElementId(
              kind: ElementKind.port,
              path: 'top.u_cpu.RST',
            ),
          ),
        );
        final inbound = await ackFuture.timeout(const Duration(seconds: 2));
        final ack = inbound.message as RequestHighlightAck;
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('not found'));
      },
    );

    test('request_highlight on scope navigates the hierarchy', () async {
      final boot = await _setup();
      addTearDown(() async {
        await boot.client.dispose();
        await boot.server.stop();
        boot.tabContainer.dispose();
        boot.rootContainer.dispose();
        try {
          boot.tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* best */
        }
      });
      final handler = CxpInboundHandler(
        server: boot.server.server!,
        rootContainer: boot.rootContainer,
        activeTabContainerLookup: () => boot.tabContainer,
      );
      addTearDown(handler.dispose);

      final ackFuture = boot.client.inbound.firstWhere(
        (m) => m.message is RequestHighlightAck,
      );
      boot.client.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.scope,
            path: 'top.u_cpu',
          ),
        ),
      );
      final inbound = await ackFuture.timeout(const Duration(seconds: 2));
      expect((inbound.message as RequestHighlightAck).honored, isTrue);

      final selected = boot.tabContainer.read(hierarchyTreeProvider).selected;
      expect(selected, isNotNull);
      expect(selected!.moduleName, 'cpu');
      expect(selected.path, <String>['u_cpu']);

      // The resolved scope row must be flashed so the navigation
      // produces a visible cue. The flash key is the node's instance path.
      final flash = boot.tabContainer.read(scopeFlashProvider);
      expect(flash, isNotNull);
      expect(flash!.pathKey, 'u_cpu');
    });

    test('inbound scope highlight flashes even when it resolves to the '
        'already-selected top scope', () async {
      final boot = await _setup();
      addTearDown(() async {
        await boot.client.dispose();
        await boot.server.stop();
        boot.tabContainer.dispose();
        boot.rootContainer.dispose();
        try {
          boot.tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* best */
        }
      });
      // setModel selects the top scope; re-selecting it is a no-op, so the
      // flash is the ONLY thing that changes on screen — the exact case that
      // used to ack honored:true yet do nothing visible.
      final before = boot.tabContainer.read(hierarchyTreeProvider).selected;
      expect(before, isNotNull);
      expect(before!.isRoot, isTrue);

      final handler = CxpInboundHandler(
        server: boot.server.server!,
        rootContainer: boot.rootContainer,
        activeTabContainerLookup: () => boot.tabContainer,
      );
      addTearDown(handler.dispose);

      final ackFuture = boot.client.inbound.firstWhere(
        (m) => m.message is RequestHighlightAck,
      );
      boot.client.send(
        const RequestHighlight(
          element: ElementId(kind: ElementKind.scope, path: 'top'),
        ),
      );
      final inbound = await ackFuture.timeout(const Duration(seconds: 2));
      expect((inbound.message as RequestHighlightAck).honored, isTrue);

      // Top scope's instance path is empty → its flash key is the empty string.
      final flash = boot.tabContainer.read(scopeFlashProvider);
      expect(flash, isNotNull);
      expect(flash!.pathKey, '');
    });

    test('request_highlight on unknown scope acks honored=false', () async {
      final boot = await _setup();
      addTearDown(() async {
        await boot.client.dispose();
        await boot.server.stop();
        boot.tabContainer.dispose();
        boot.rootContainer.dispose();
        try {
          boot.tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* best */
        }
      });
      final handler = CxpInboundHandler(
        server: boot.server.server!,
        rootContainer: boot.rootContainer,
        activeTabContainerLookup: () => boot.tabContainer,
      );
      addTearDown(handler.dispose);

      final ackFuture = boot.client.inbound.firstWhere(
        (m) => m.message is RequestHighlightAck,
      );
      boot.client.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.scope,
            path: 'top.no_such_instance',
          ),
        ),
      );
      final ack =
          (await ackFuture.timeout(const Duration(seconds: 2))).message
              as RequestHighlightAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('not found'));
    });

    test('request_open_source shells the configured editor', () async {
      final boot = await _setup();
      addTearDown(() async {
        await boot.client.dispose();
        await boot.server.stop();
        boot.tabContainer.dispose();
        boot.rootContainer.dispose();
        try {
          boot.tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* best */
        }
      });
      // Override editor command via the app settings notifier.
      await boot.rootContainer
          .read(appSettingsProvider.notifier)
          .setCxpEditorCommand('echo {file}:{line}');

      // Capture what executable + args got launched.
      String? capturedExecutable;
      List<String>? capturedArgs;
      final mockEditor = EditorOpenService(
        processRunner: (exe, args) async {
          capturedExecutable = exe;
          capturedArgs = args;
          return ProcessResult(0, 0, '', '');
        },
      );

      final handler = CxpInboundHandler(
        server: boot.server.server!,
        rootContainer: boot.rootContainer,
        activeTabContainerLookup: () => boot.tabContainer,
        editorService: mockEditor,
      );
      addTearDown(handler.dispose);

      final ackFuture = boot.client.inbound.firstWhere(
        (m) => m.message is RequestOpenSourceAck,
      );
      boot.client.send(
        RequestOpenSource(
          filePath: _abs('/abs/path/cpu.v'),
          line: 42,
        ),
      );
      final ack =
          (await ackFuture.timeout(const Duration(seconds: 2))).message
              as RequestOpenSourceAck;
      expect(ack.honored, isTrue);
      expect(capturedExecutable, 'echo');
      expect(capturedArgs, contains('${_abs('/abs/path/cpu.v')}:42'));
    });

    // `filePath` is whatever reached the socket. The end-to-end assertion is
    // that the refusal happens before any spawn *and* travels back to the
    // peer as a reason, so a legitimate caller sending a relative path learns
    // why instead of seeing silence. Since wire 1.2 the refusal comes from
    // `LocalCxpServer`'s containment gate, which answers the ack itself and
    // never dispatches — the handler is not reached at all.
    test('request_open_source refuses a filePath that is not a path', () async {
      final boot = await _setup();
      addTearDown(() async {
        await boot.client.dispose();
        await boot.server.stop();
        boot.tabContainer.dispose();
        boot.rootContainer.dispose();
        try {
          boot.tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* best */
        }
      });
      await boot.rootContainer
          .read(appSettingsProvider.notifier)
          .setCxpEditorCommand('vim +{line} {file}');

      var spawned = false;
      final handler = CxpInboundHandler(
        server: boot.server.server!,
        rootContainer: boot.rootContainer,
        activeTabContainerLookup: () => boot.tabContainer,
        editorService: EditorOpenService(
          processRunner: (exe, args) async {
            spawned = true;
            return ProcessResult(0, 0, '', '');
          },
        ),
      );
      addTearDown(handler.dispose);

      final ackFuture = boot.client.inbound.firstWhere(
        (m) => m.message is RequestOpenSourceAck,
      );
      // An argv element beginning with `+` is an ex command to vim, and a
      // colon in position 1 is what defeats a drive-letter absoluteness
      // guess.
      boot.client.send(
        const RequestOpenSource(filePath: '+:!curl x|sh', line: 42),
      );
      final refusal =
          (await ackFuture.timeout(const Duration(seconds: 2))).message
              as RequestOpenSourceAck;
      expect(refusal.honored, isFalse);
      expect(refusal.reason, contains('must be an absolute path'));
      expect(spawned, isFalse, reason: 'no editor may be launched');
    });

    // CXP §11's SHOULD: resolve the path against the directories the user has
    // already opened and refuse the rest. `/etc/shadow` is a perfectly
    // absolute path, and every check NetCrux carried before wire 1.2 let it
    // through to the editor argv. The wire screen is the floor, so the
    // handler's rooted check is the one that refuses it.
    //
    // MUTATION: deleting the `_containment.refuse(filePath)` check in
    // `_openSource`, or `roots` from the rule, makes this red.
    test(
      'request_open_source refuses a path outside the open directories',
      () async {
        final boot = await _setup();
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        await boot.rootContainer
            .read(appSettingsProvider.notifier)
            .setCxpEditorCommand('vim +{line} {file}');

        var spawned = false;
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
          editorService: EditorOpenService(
            processRunner: (exe, args) async {
              spawned = true;
              return ProcessResult(0, 0, '', '');
            },
          ),
        );
        addTearDown(handler.dispose);

        final ackFuture = boot.client.inbound.firstWhere(
          (m) => m.message is RequestOpenSourceAck,
        );
        boot.client.send(
          RequestOpenSource(filePath: _abs('/etc/shadow'), line: 1),
        );
        final refusal =
            (await ackFuture.timeout(const Duration(seconds: 2))).message
                as RequestOpenSourceAck;
        expect(refusal.honored, isFalse);
        expect(refusal.reason, contains('outside the directories'));
        expect(
          refusal.reason,
          isNot(contains(_abs('/etc/shadow'))),
          reason: 'the reason rides back to the sender (CXP §9.11)',
        );
        expect(spawned, isFalse, reason: 'no editor may be launched');
      },
    );

    test(
      'request_open_source with empty editor command acks honored=false',
      () async {
        final boot = await _setup();
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        await boot.rootContainer
            .read(appSettingsProvider.notifier)
            .setCxpEditorCommand('');

        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
          editorService: EditorOpenService(
            processRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          ),
        );
        addTearDown(handler.dispose);

        final ackFuture = boot.client.inbound.firstWhere(
          (m) => m.message is RequestOpenSourceAck,
        );
        boot.client.send(
          RequestOpenSource(filePath: _abs('/abs/path/foo.v'), line: 1),
        );
        final ack =
            (await ackFuture.timeout(const Duration(seconds: 2))).message
                as RequestOpenSourceAck;
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('No editor command configured'));
      },
    );

    test('request_highlight when no active tab acks honored=false', () async {
      final boot = await _setup();
      addTearDown(() async {
        await boot.client.dispose();
        await boot.server.stop();
        boot.tabContainer.dispose();
        boot.rootContainer.dispose();
        try {
          boot.tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* best */
        }
      });
      final handler = CxpInboundHandler(
        server: boot.server.server!,
        rootContainer: boot.rootContainer,
        activeTabContainerLookup: () => null,
      );
      addTearDown(handler.dispose);

      final ackFuture = boot.client.inbound.firstWhere(
        (m) => m.message is RequestHighlightAck,
      );
      boot.client.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.instance,
            path: 'top.u_cpu:cell',
          ),
        ),
      );
      final ack =
          (await ackFuture.timeout(const Duration(seconds: 2))).message
              as RequestHighlightAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('No active tab'));
    });

    test(
      'request_highlight with a WAVEFORM-style signal name leaf-matches the '
      'netlist net (reverse cross-probe)',
      () async {
        // WaveCrux sends its waveform signal identity — a testbench hierarchy
        // path with kind `signal` — which does not match NetCrux's synthesized
        // netlist scope. The inbound resolver must strip the tb hierarchy and
        // leaf-match `data` against the current scope's net.
        final boot = await _setup(model: _modelWithNet());
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
        );
        addTearDown(handler.dispose);

        final ackFuture = boot.client.inbound.firstWhere(
          (m) => m.message is RequestHighlightAck,
        );
        boot.client.send(
          const RequestHighlight(
            element: ElementId(
              kind: ElementKind.signal,
              path: 'tb_top.dut.data',
            ),
          ),
        );
        final inbound = await ackFuture.timeout(const Duration(seconds: 2));
        expect((inbound.message as RequestHighlightAck).honored, isTrue);

        final selection = boot.tabContainer.read(selectedElementProvider);
        expect(selection.primary, isA<SelectedElementWire>());
        expect((selection.primary as SelectedElementWire).netId, 7);
      },
    );

    test(
      'request_highlight with a BARE leaf name leaf-matches the netlist net',
      () async {
        final boot = await _setup(model: _modelWithNet());
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
        );
        addTearDown(handler.dispose);

        final ackFuture = boot.client.inbound.firstWhere(
          (m) => m.message is RequestHighlightAck,
        );
        boot.client.send(
          const RequestHighlight(
            element: ElementId(kind: ElementKind.signal, path: 'data'),
          ),
        );
        final inbound = await ackFuture.timeout(const Duration(seconds: 2));
        expect((inbound.message as RequestHighlightAck).honored, isTrue);
        expect(
          boot.tabContainer.read(selectedElementProvider).primary,
          isA<SelectedElementWire>(),
        );
      },
    );

    test(
      'inbound notify_selection live-highlights a signal-like element '
      '(no ack, symmetric to WaveCrux)',
      () async {
        final boot = await _setup(model: _modelWithNet());
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
        );
        addTearDown(handler.dispose);

        final selected = Completer<void>();
        final sub = boot.tabContainer.listen(
          selectedElementProvider,
          (_, next) {
            if (next.primary is SelectedElementWire && !selected.isCompleted) {
              selected.complete();
            }
          },
        );
        addTearDown(sub.close);

        boot.client.send(
          const NotifySelection(
            elements: <ElementId>[
              ElementId(kind: ElementKind.signal, path: 'tb_top.dut.data'),
            ],
            displayName: 'data',
          ),
        );
        await selected.future.timeout(const Duration(seconds: 2));
        expect(
          (boot.tabContainer.read(selectedElementProvider).primary
                  as SelectedElementWire)
              .netId,
          7,
        );
      },
    );

    test(
      'request_highlight for a NOT-open design opens it via the shared workspace and selects '
      'the element once elaboration lands',
      () async {
        const designId = 'design-fsm-lock';
        final storeDir = Directory.systemTemp.createTempSync('cxp_wsE_');
        // The workspace store prunes artifacts whose file no longer exists, so
        // the recorded source must be a real path.
        final sourceFile = File('${storeDir.path}/fsm_lock.v')
          ..writeAsStringSync('module fsm_lock(); endmodule\n');
        // Written WITHOUT the rule: a producer records what it produced, and
        // which of it a consumer may open is the consumer's rule.
        await CxpWorkspaceStore(
          workspaceDirectory: storeDir.path,
        ).upsertArtifact(
          designId: designId,
          kind: 'source',
          path: sourceFile.path,
          producer: 'netcrux',
        );
        final store = CxpWorkspaceStore(
          workspaceDirectory: storeDir.path,
          containment: CxpPathContainment(
            roots: () => <String>[storeDir.path],
          ),
        );

        // No model loaded — the design is not open, so the local resolve must
        // miss and the shared-workspace fallback must open it. The design's
        // own directory is the open root: in the running app it is one
        // because the user opened a file there.
        final boot = await _setup(
          loadModel: false,
          openDirectories: <String>[storeDir.path],
          rootOverrides: <Override>[
            cxpWorkspaceStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
            storeDir.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
        );
        addTearDown(handler.dispose);

        final ackFuture = boot.client.inbound.firstWhere(
          (m) => m.message is RequestHighlightAck,
        );
        boot.client.send(
          const RequestHighlight(
            element: ElementId(
              kind: ElementKind.signal,
              path: 'tb_top.dut.data',
            ),
            metadata: <String, Object?>{cxpDesignIdMetadataKey: designId},
          ),
        );
        final ack =
            (await ackFuture.timeout(const Duration(seconds: 2))).message
                as RequestHighlightAck;
        // Honored: the design's source was opened from the shared workspace.
        expect(ack.honored, isTrue);
        expect(
          boot.tabContainer.read(currentProjectProvider).sourceFiles,
          <String>[sourceFile.path],
        );

        // Elaboration is async in production; simulate it completing. The
        // deferred one-shot select must then fire on the now-loaded design.
        boot.tabContainer
            .read(hierarchyTreeProvider.notifier)
            .setModel(_modelWithNet());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          boot.tabContainer.read(selectedElementProvider).primary,
          isA<SelectedElementWire>(),
        );
      },
    );

    // End to end over the socket: a peer published a design NetCrux has
    // never opened and asks for it by `design_id` alone — the VS Code
    // extension's "Open in NetCrux Desktop". The store the app provides is
    // rooted and drops the record; `request_open_artifact` reads the same
    // records under the floor (`kCxpOpenArtifactContainment` says why), so
    // the design is loaded. The route's refusals — relative, NUL, padded —
    // are proven in `cxp_open_artifact_test.dart`.
    //
    // MUTATION: resolving through `resolveDesignSourceArtifactPath` (the
    // rooted store) in `_resolveOpenArtifact` makes this red.
    test(
      'request_open_artifact opens a recorded design outside the open '
      'directories',
      () async {
        const designId = 'design-outside';
        final storeDir = Directory.systemTemp.createTempSync('cxp_ws_out_');
        final elsewhere = Directory.systemTemp.createTempSync('cxp_out_src_');
        final sourceFile = File('${elsewhere.path}/never_opened.v')
          ..writeAsStringSync('module never_opened(); endmodule\n');
        await CxpWorkspaceStore(
          workspaceDirectory: storeDir.path,
        ).upsertArtifact(
          designId: designId,
          kind: 'source',
          path: sourceFile.path,
          producer: 'vscode',
        );
        final containment = CxpPathContainment(
          roots: () => <String>[storeDir.path],
        );
        final store = CxpWorkspaceStore(
          workspaceDirectory: storeDir.path,
          containment: containment,
        );

        final boot = await _setup(
          loadModel: false,
          openDirectories: <String>[storeDir.path],
          rootOverrides: <Override>[
            cxpWorkspaceStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
            storeDir.deleteSync(recursive: true);
            elsewhere.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
        );
        addTearDown(handler.dispose);

        final ackFuture = boot.client.inbound.firstWhere(
          (m) => m.message is RequestOpenArtifactAck,
        );
        boot.client.send(
          const RequestOpenArtifact(
            designId: designId,
            artifactKind: 'source',
          ),
        );
        final ack =
            (await ackFuture.timeout(const Duration(seconds: 2))).message
                as RequestOpenArtifactAck;
        expect(ack.honored, isTrue, reason: ack.reason);
        expect(
          boot.tabContainer.read(currentProjectProvider).sourceFiles,
          <String>[sourceFile.path],
        );
      },
    );
  });

  group('real reset_domains B→A leaf-match (yosys-gated)', () {
    test(
      'the EXACT fullPaths WaveCrux emits (clk, a multi-bit bus, a sliced bus, '
      'and the alarm_r register) each resolve + select, honored:true',
      () async {
        final probe = await YosysAvailabilityService(
          runner: const DefaultProcessRunner(),
        ).probe();
        if (!probe.isAvailable) {
          markTestSkipped('yosys not on PATH — skipping real elaboration');
          return;
        }
        final run = await YosysRunner().run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile(_resetDomainsVPath)],
            topModule: 'reset_domains',
          ),
        );
        final model = const YosysJsonParser().parse(
          (run as YosysRunSuccess).rawJson,
        );

        // NetCrux elaborated `reset_domains` as top; setModel selects the root
        // scope (the design root the user highlights — the live repro state).
        final boot = await _setup(model: model);
        addTearDown(() async {
          await boot.client.dispose();
          await boot.server.stop();
          boot.tabContainer.dispose();
          boot.rootContainer.dispose();
          try {
            boot.tmp.deleteSync(recursive: true);
          } on FileSystemException {
            /* best */
          }
        });
        final handler = CxpInboundHandler(
          server: boot.server.server!,
          rootContainer: boot.rootContainer,
          activeTabContainerLookup: () => boot.tabContainer,
        );
        addTearDown(handler.dispose);

        // WaveCrux emits the selected variable's `fullPath` (kind: signal). Its
        // VCD comes from `$dumpvars(0, dut)`, so the scope is
        // `tb_reset_domains.dut.<sig>` — a differently-rooted testbench path
        // that must still leaf-match NetCrux's `reset_domains` netlist. A
        // multi-bit bus may arrive sliced (`data_r[7:0]`). Every one used to
        // reply honored:false "Element not found" (the live B→A bug).
        Future<void> expectResolves(String path) async {
          final ackFuture = boot.client.inbound.firstWhere(
            (m) => m.message is RequestHighlightAck,
          );
          boot.client.send(
            RequestHighlight(
              element: ElementId(kind: ElementKind.signal, path: path),
            ),
          );
          final ack =
              (await ackFuture.timeout(const Duration(seconds: 2))).message
                  as RequestHighlightAck;
          expect(
            ack.honored,
            isTrue,
            reason: 'WaveCrux path "$path" must resolve against the netlist',
          );
          expect(
            boot.tabContainer.read(selectedElementProvider).primary,
            isNot(isA<SelectedElementNone>()),
            reason: 'path "$path" must select something on the schematic',
          );
        }

        await expectResolves('tb_reset_domains.dut.clk');
        await expectResolves('tb_reset_domains.dut.arm');
        await expectResolves('tb_reset_domains.dut.data_r');
        // Sliced multi-bit bus — exercises the bus-bit-select suffix strip.
        await expectResolves('tb_reset_domains.dut.data_r[7:0]');
        // The register (the outbound side emits `alarm_r`; the reverse must
        // resolve it too).
        await expectResolves('tb_reset_domains.dut.alarm_r');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('EditorOpenService', () {
    test('substitutes {file}, {line}, {column}', () async {
      String? exe;
      List<String>? args;
      final service = EditorOpenService(
        processRunner: (e, a) async {
          exe = e;
          args = a;
          return ProcessResult(0, 0, '', '');
        },
      );
      final result = await service.openSourceLocation(
        commandTemplate: 'code -g {file}:{line}:{column}',
        filePath: '/src/cpu.v',
        line: 12,
        column: 5,
      );
      expect(result.honored, isTrue);
      expect(exe, 'code');
      expect(args, ['-g', '/src/cpu.v:12:5']);
    });

    test('non-zero exit code yields honored=false', () async {
      final service = EditorOpenService(
        processRunner: (_, _) async => ProcessResult(0, 1, '', 'boom'),
      );
      final result = await service.openSourceLocation(
        commandTemplate: 'code {file}',
        filePath: '/x.v',
        line: 1,
      );
      expect(result.honored, isFalse);
      expect(result.reason, contains('exit'));
    });

    test('ProcessException yields honored=false', () async {
      final service = EditorOpenService(
        processRunner: (_, _) async =>
            throw const ProcessException('codex', [], 'not found', 2),
      );
      final result = await service.openSourceLocation(
        commandTemplate: 'codex {file}:{line}',
        filePath: '/x.v',
        line: 1,
      );
      expect(result.honored, isFalse);
      expect(result.reason, contains('Failed to launch'));
    });

    test('empty command yields honored=false', () async {
      final service = EditorOpenService(
        processRunner: (_, _) async => ProcessResult(0, 0, '', ''),
      );
      final result = await service.openSourceLocation(
        commandTemplate: '',
        filePath: '/x.v',
        line: 1,
      );
      expect(result.honored, isFalse);
      expect(result.reason, contains('No editor command configured'));
    });
  });
}
