// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/remote/cxp/cxp_inbound_handler.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// `request_open_artifact`: a peer asks NetCrux to open a design's source,
/// named by `design_id`, with an optional `path` hint. NetCrux resolves the
/// file through the shared workspace store, falls back to the hint, and
/// loads the result into the active tab — so every path that reaches
/// `setSourceFiles` here was chosen, directly or through a record, by
/// another process.
///
/// The route is held to the floor — absolute, well-formed, the exact string
/// loaded — and not to the directories the user has opened: it exists to
/// open a design NetCrux has never seen (`kCxpOpenArtifactContainment` says
/// why). The `crux.design_id` fallback a highlight takes keeps the roots,
/// and the last group proves that it still does.
///
/// `LocalCxpServer` screens a hint on the wire first, so a socket-level
/// test cannot tell whether the handler checks at all; most tests here
/// deliver the request through [_ScriptedServer], which hands the handler
/// exactly what a peer sent. Two tests go through a real socket, one of them
/// through the server the app's own provider builds.
void main() {
  // An honored open nudges the window's attention through a platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory open;
  late Directory outside;
  late Directory storeDir;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    open = Directory.systemTemp.createTempSync('cxp_artifact_open_');
    outside = Directory.systemTemp.createTempSync('cxp_artifact_outside_');
    storeDir = Directory.systemTemp.createTempSync('cxp_artifact_store_');
  });

  tearDown(() {
    for (final dir in <Directory>[open, outside, storeDir]) {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort.
      }
    }
  });

  File design(Directory dir, String name) =>
      File(p.join(dir.path, name))..writeAsStringSync(
        'module ${p.basenameWithoutExtension(name).trim()}; endmodule\n',
      );

  Future<void> record(String designId, String path) =>
      CxpWorkspaceStore(workspaceDirectory: storeDir.path).upsertArtifact(
        designId: designId,
        kind: 'source',
        path: path,
        producer: 'peer',
      );

  /// A handler whose rooted rule has [open] as its only root, over a
  /// workspace store that carries that rule — as the production store does.
  /// Nothing on the `request_open_artifact` route should consult either.
  ({_ScriptedServer server, ProviderContainer tab}) boot({
    bool withTab = true,
  }) {
    final containment = CxpPathContainment(roots: () => <String>[open.path]);
    final root = ProviderContainer(
      overrides: <Override>[
        ...netcruxTelemetryTestOverrides(),
        cxpPathContainmentProvider.overrideWithValue(containment),
        cxpWorkspaceStoreProvider.overrideWithValue(
          CxpWorkspaceStore(
            workspaceDirectory: storeDir.path,
            containment: containment,
          ),
        ),
      ],
    );
    addTearDown(root.dispose);
    final tab = ProviderContainer(parent: root);
    addTearDown(tab.dispose);
    final server = _ScriptedServer();
    final handler = CxpInboundHandler(
      server: server,
      rootContainer: root,
      activeTabContainerLookup: () => withTab ? tab : null,
    );
    addTearDown(handler.dispose);
    return (server: server, tab: tab);
  }

  List<String> loaded(ProviderContainer tab) =>
      tab.read(currentProjectProvider).sourceFiles;

  group('request_open_artifact', () {
    test('a recorded source inside the open directories is loaded into the '
        'active tab', () async {
      final file = design(open, 'fsm.v');
      await record('d1', file.path);
      final env = boot();
      final ack = await env.server.ask(
        const RequestOpenArtifact(designId: 'd1', artifactKind: 'source'),
      );
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(ack.reason, isNull);
      expect(loaded(env.tab), <String>[file.path]);
    });

    test(
      'a kind other than source is declined, and nothing is loaded',
      () async {
        final file = design(open, 'fsm.v');
        await record('d1', file.path);
        final env = boot();
        final ack = await env.server.ask(
          RequestOpenArtifact(
            designId: 'd1',
            artifactKind: 'waveform',
            path: file.path,
          ),
        );
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('only source artifacts'));
        expect(loaded(env.tab), isEmpty);
      },
    );

    test('no record and no hint is declined', () async {
      final env = boot();
      final ack = await env.server.ask(
        const RequestOpenArtifact(designId: 'unknown', artifactKind: 'source'),
      );
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('no source artifact recorded'));
      expect(loaded(env.tab), isEmpty);
    });

    test('with no record, the peer hint inside the open directories is '
        'loaded', () async {
      final file = design(open, 'hinted.v');
      final env = boot();
      final ack = await env.server.ask(
        RequestOpenArtifact(
          designId: 'unrecorded',
          artifactKind: 'source',
          path: file.path,
        ),
      );
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(loaded(env.tab), <String>[file.path]);
    });

    // The design the VS Code extension hands over is, as often as not, one
    // NetCrux has never opened. MUTATION: checking the hint with the rooted
    // `_containment.refuse(path)` in `_resolveOpenArtifact` instead of
    // `kCxpOpenArtifactContainment.refuse(path)` makes this red.
    test('with no record, a peer hint outside the open directories is '
        'loaded: the floor applies, not the roots', () async {
      final file = design(outside, 'never_opened.v');
      final env = boot();
      final ack = await env.server.ask(
        RequestOpenArtifact(
          designId: 'unrecorded',
          artifactKind: 'source',
          path: file.path,
        ),
      );
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(loaded(env.tab), <String>[file.path]);
    });

    // The extension publishes the file into the shared workspace before it
    // sends, so this is the path its hand-off normally takes. The store the
    // app provides is rooted and would drop the record; the route reads the
    // same directory under the floor. MUTATION: resolving through
    // `resolveDesignSourceArtifactPath` (the rooted store) in
    // `_resolveOpenArtifact` makes this red.
    test('a record outside the open directories is loaded, though the rooted '
        'store drops it', () async {
      final file = design(outside, 'published.v');
      await record('d-published', file.path);
      final env = boot();
      final ack = await env.server.ask(
        const RequestOpenArtifact(
          designId: 'd-published',
          artifactKind: 'source',
        ),
      );
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(loaded(env.tab), <String>[file.path]);
    });

    test('a record inside the open directories wins over a hint outside '
        'them', () async {
      final recorded = design(open, 'recorded.v');
      final hinted = design(outside, 'hinted.v');
      await record('d2', recorded.path);
      final env = boot();
      final ack = await env.server.ask(
        RequestOpenArtifact(
          designId: 'd2',
          artifactKind: 'source',
          path: hinted.path,
        ),
      );
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(loaded(env.tab), <String>[recorded.path]);
    });

    // The receiver's own resolution comes first (CXP §9.10), wherever the
    // record points. MUTATION: resolving through the rooted store makes this
    // fall back to the hint, and it goes red.
    test('a record outside the open directories still wins over a hint '
        'inside them', () async {
      final recorded = design(outside, 'recorded.v');
      final hinted = design(open, 'hinted.v');
      await record('d3', recorded.path);
      final env = boot();
      final ack = await env.server.ask(
        RequestOpenArtifact(
          designId: 'd3',
          artifactKind: 'source',
          path: hinted.path,
        ),
      );
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(loaded(env.tab), <String>[recorded.path]);
    });

    test('a malformed hint is refused before anything is loaded, and the '
        'reason never repeats it', () async {
      final inside = design(open, 'real.v').path;
      final hints = <String>[
        '',
        '   ',
        'relative/design.v',
        './design.v',
        '../${p.basename(open.path)}/real.v',
        '-rf',
        '+:!curl x|sh',
        '$inside .v',
        'file://$inside',
        ' $inside',
        '$inside\n',
      ];
      final env = boot();
      for (final hint in hints) {
        final ack = await env.server.ask(
          RequestOpenArtifact(
            designId: 'unrecorded',
            artifactKind: 'source',
            path: hint,
          ),
        );
        expect(ack.honored, isFalse, reason: 'hint ${hint.codeUnits}');
        if (hint.trim().isNotEmpty) {
          expect(ack.reason, isNot(contains(hint.trim())));
        }
        expect(loaded(env.tab), isEmpty, reason: 'hint ${hint.codeUnits}');
      }
    });

    // The floor is what stands between a peer and a load now, so each of its
    // refusals is pinned by a case only it can refuse.
    group('the floor refuses', () {
      // Relative to where NetCrux runs, this names a real design, so nothing
      // after the floor would stop it. MUTATION: deleting the
      // `kCxpOpenArtifactContainment.refuse(path)` check loads it, and this
      // goes red.
      test('a relative path, even one naming a file from where NetCrux '
          'runs', () async {
        // Under the working directory rather than the system temp: on
        // Windows those can sit on different drives, and no relative path
        // crosses a drive. `.dart_tool` exists wherever tests run and is
        // never committed.
        final here = Directory(
          p.join(Directory.current.path, '.dart_tool'),
        ).createTempSync('cxp_artifact_relative_');
        addTearDown(() {
          try {
            here.deleteSync(recursive: true);
          } on FileSystemException {
            // Best effort.
          }
        });
        final relative = p.relative(design(here, 'relative.v').path);
        expect(p.isRelative(relative), isTrue);
        expect(
          FileSystemEntity.typeSync(relative),
          FileSystemEntityType.file,
          reason: 'the case must name a real file, or it proves nothing',
        );
        final env = boot();
        final ack = await env.server.ask(
          RequestOpenArtifact(
            designId: 'unrecorded',
            artifactKind: 'source',
            path: relative,
          ),
        );
        expect(ack.honored, isFalse);
        expect(ack.reason, 'file_path must be an absolute path');
        expect(loaded(env.tab), isEmpty);
      });

      // A NUL ends the name where the operating system reads it, so what was
      // checked is not what would be opened.
      test('a path carrying a NUL', () async {
        final file = design(open, 'nul.v');
        final env = boot();
        for (final hint in <String>[
          '${file.path}\u0000',
          '${file.path}\u0000.txt',
          '${open.path}\u0000/nul.v',
        ]) {
          final ack = await env.server.ask(
            RequestOpenArtifact(
              designId: 'unrecorded',
              artifactKind: 'source',
              path: hint,
            ),
          );
          expect(ack.honored, isFalse, reason: 'hint ${hint.codeUnits}');
          expect(ack.reason, 'file_path contains a NUL character');
          expect(loaded(env.tab), isEmpty, reason: 'hint ${hint.codeUnits}');
        }
      });

      // The string checked is the string loaded. A trailing space is part of a
      // POSIX file name, so `padded.v ` is a real file here and a different
      // one from `padded.v`; a check that trimmed first would pass the one
      // name and load the other. The refusal and its reason are crux_cxp's
      // own floor rule; NetCrux adds no clause of its own, so this case is
      // what proves the shared rule holds on this route. MUTATION: deleting
      // the `kCxpOpenArtifactContainment.refuse(path)` check loads
      // `padded.v `, and this goes red.
      test('a path padded with white space, though the padded name is a real '
          'file', () async {
        design(open, 'padded.v');
        final trailing = design(open, 'padded.v ').path;
        expect(
          FileSystemEntity.typeSync(trailing),
          FileSystemEntityType.file,
          reason: 'the case must name a real file, or it proves nothing',
        );
        final plain = p.join(open.path, 'padded.v');
        final env = boot();
        for (final hint in <String>[trailing, ' $plain', '$plain\t']) {
          final ack = await env.server.ask(
            RequestOpenArtifact(
              designId: 'unrecorded',
              artifactKind: 'source',
              path: hint,
            ),
          );
          expect(ack.honored, isFalse, reason: 'hint ${hint.codeUnits}');
          expect(ack.reason, 'file_path begins or ends with white space');
          expect(loaded(env.tab), isEmpty, reason: 'hint ${hint.codeUnits}');
        }

        // The same name arriving as a record rather than a hint.
        await record('d-padded', trailing);
        final ack = await env.server.ask(
          const RequestOpenArtifact(
            designId: 'd-padded',
            artifactKind: 'source',
          ),
        );
        expect(ack.honored, isFalse);
        expect(loaded(env.tab), isEmpty);
      });
    });

    test('a hint naming a file that does not exist is declined, and the '
        'active tab keeps its design', () async {
      final current = design(open, 'current.v');
      final env = boot();
      env.tab.read(currentProjectProvider.notifier).setSourceFiles(<String>[
        current.path,
      ]);
      for (final missing in <String>[
        p.join(open.path, 'deleted.v'),
        p.join(open.path, 'no', 'such', 'dir.v'),
        open.path, // a directory, not a file
      ]) {
        final ack = await env.server.ask(
          RequestOpenArtifact(
            designId: 'unrecorded',
            artifactKind: 'source',
            path: missing,
          ),
        );
        expect(ack.honored, isFalse, reason: missing);
        expect(ack.reason, 'the artifact is not a file here');
        expect(loaded(env.tab), <String>[current.path]);
      }
    });

    test('no active tab is declined', () async {
      final file = design(open, 'fsm.v');
      await record('d1', file.path);
      final env = boot(withTab: false);
      final ack = await env.server.ask(
        const RequestOpenArtifact(designId: 'd1', artifactKind: 'source'),
      );
      expect(ack.honored, isFalse);
      expect(ack.reason, 'No active tab');
    });

    // End to end over a real socket, through the server the app's own
    // provider builds: `LocalCxpServer` screens the hint on the wire before
    // the handler sees it, and a rooted screen there strips the hint for a
    // design never opened. No record is written, so the hint is all the
    // handler has. MUTATION: handing `NetcruxCxpServer` the rooted
    // `cxpPathContainmentProvider` in `CxpServerHost.build` makes this red.
    test('over a socket, the production server passes a hint for a design '
        'never opened, and it is loaded', () async {
      final file = design(outside, 'never_opened.v');
      final peers = Directory.systemTemp.createTempSync('cxp_artifact_peers_');
      addTearDown(() => _deleteQuietly(peers));
      final root = ProviderContainer(
        overrides: <Override>[
          ...netcruxTelemetryTestOverrides(),
          appSettingsProvider.overrideWith(_CxpOnEphemeralPort.new),
          cxpManifestDirectoryProvider.overrideWith((ref) async => peers.path),
          // The build-info lookup waits on a platform channel the test
          // binding never answers.
          netcruxProductVersionProvider.overrideWith(
            (ref) async => '0.0.0-test',
          ),
          cxpWorkspaceDirectoryProvider.overrideWithValue(storeDir.path),
          cxpPathContainmentProvider.overrideWithValue(
            CxpPathContainment(roots: () => <String>[open.path]),
          ),
        ],
      );
      addTearDown(root.dispose);
      final host = (await root.read(cxpServerHostProvider.future))!;
      final tab = ProviderContainer(parent: root);
      addTearDown(tab.dispose);
      final handler = CxpInboundHandler(
        server: host.server!,
        rootContainer: root,
        activeTabContainerLookup: () => tab,
      );
      addTearDown(handler.dispose);
      final client = await _connect(host.boundPort!);

      final reply = client.inbound.firstWhere(
        (m) => m.message is RequestOpenArtifactAck,
      );
      client.send(
        RequestOpenArtifact(
          designId: 'unrecorded',
          artifactKind: 'source',
          path: file.path,
        ),
      );
      final ack =
          (await reply.timeout(const Duration(seconds: 5))).message
              as RequestOpenArtifactAck;
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(loaded(tab), <String>[file.path]);
    });

    // The wire screen is the same floor, and it refuses a padded path, so the
    // hint is dropped before the handler sees it and the design id, which
    // nothing recorded, resolves to nothing. Over a real socket that is the
    // route a padded hint takes, and nothing is loaded. MUTATION: a floor
    // that trims before it judges, in the wire screen and in
    // `_resolveOpenArtifact` alike, loads `padded.v `, and this goes red.
    test('over a socket, a padded hint is refused and nothing is '
        'loaded', () async {
      design(open, 'padded.v');
      final trailing = design(open, 'padded.v ').path;
      final peers = Directory.systemTemp.createTempSync('cxp_artifact_peers_');
      addTearDown(() => _deleteQuietly(peers));
      final server = NetcruxCxpServer(
        productVersion: '0.0.0-test',
        manifestDirectory: p.join(peers.path, 'peers'),
        containment: kCxpOpenArtifactContainment,
      );
      await server.start();
      addTearDown(server.stop);
      final root = ProviderContainer(
        overrides: <Override>[
          ...netcruxTelemetryTestOverrides(),
          cxpPathContainmentProvider.overrideWithValue(
            CxpPathContainment(roots: () => <String>[open.path]),
          ),
          cxpWorkspaceStoreProvider.overrideWithValue(
            CxpWorkspaceStore(workspaceDirectory: storeDir.path),
          ),
        ],
      );
      addTearDown(root.dispose);
      final tab = ProviderContainer(parent: root);
      addTearDown(tab.dispose);
      final handler = CxpInboundHandler(
        server: server.server!,
        rootContainer: root,
        activeTabContainerLookup: () => tab,
      );
      addTearDown(handler.dispose);
      final client = await _connect(server.boundPort!);

      final reply = client.inbound.firstWhere(
        (m) => m.message is RequestOpenArtifactAck,
      );
      client.send(
        RequestOpenArtifact(
          designId: 'unrecorded',
          artifactKind: 'source',
          path: trailing,
        ),
      );
      final ack =
          (await reply.timeout(const Duration(seconds: 5))).message
              as RequestOpenArtifactAck;
      expect(ack.honored, isFalse);
      expect(loaded(tab), isEmpty);
    });
  });

  // Everything above fixes the roots. These run the production provider —
  // `cxpPathContainmentProvider` as the app builds it — over a real workspace
  // with one open tab and a recent-files list, so the roots under test are
  // the ones NetCrux actually uses.
  group('with the production roots', () {
    late Directory tabDir;
    late Directory recentDir;
    late Directory neverDir;
    late Directory workspaceDir;

    setUp(() {
      tabDir = Directory.systemTemp.createTempSync('cxp_roots_tab_');
      recentDir = Directory.systemTemp.createTempSync('cxp_roots_recent_');
      neverDir = Directory.systemTemp.createTempSync('cxp_roots_never_');
      workspaceDir = Directory.systemTemp.createTempSync('cxp_roots_ws_');
      addTearDown(() {
        for (final dir in <Directory>[
          tabDir,
          recentDir,
          neverDir,
          workspaceDir,
        ]) {
          try {
            dir.deleteSync(recursive: true);
          } on FileSystemException {
            // Best effort.
          }
        }
      });
    });

    Future<
      ({_ScriptedServer server, ProviderContainer root, ProviderContainer tab})
    >
    bootApp() async {
      final recent = design(recentDir, 'closed.v');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'netcrux.recentSourceFilePaths': <String>[recent.path],
      });
      final root = ProviderContainer(
        overrides: <Override>[
          ...netcruxTelemetryTestOverrides(),
          netcruxWorkspaceProvider.overrideWith(
            () => NetcruxWorkspaceNotifier(
              service: WorkspaceService<NetcruxTabPayload>(
                codec: const NetcruxWorkspaceCodec(),
                directoryFactory: () async => workspaceDir,
                logger: (_) {},
              ),
              restoreGate: () async => true,
            ),
          ),
          // The production store provider, pointed at a temp directory.
          cxpWorkspaceDirectoryProvider.overrideWithValue(storeDir.path),
        ],
      );
      addTearDown(root.dispose);
      await root.read(netcruxWorkspaceProvider.future);
      await root
          .read(netcruxWorkspaceProvider.notifier)
          .openTab(
            displayName: 'open',
            payload: NetcruxTabPayload(
              sourceFiles: <String>[design(tabDir, 'open.v').path],
            ),
          );
      await root.read(appSettingsProvider.future);
      final tab = ProviderContainer(parent: root);
      addTearDown(tab.dispose);
      final server = _ScriptedServer();
      final handler = CxpInboundHandler(
        server: server,
        rootContainer: root,
        activeTabContainerLookup: () => tab,
      );
      addTearDown(handler.dispose);
      return (server: server, root: root, tab: tab);
    }

    // The store applies the rule to what it resolves, before the handler
    // ever sees the path. MUTATION: dropping `containment:` from
    // `cxpWorkspaceStoreProvider` turns this red.
    test('the workspace store resolves a record in the open directories and '
        'drops one outside them', () async {
      final env = await bootApp();
      final inTab = design(tabDir, 'kept.v');
      final never = design(neverDir, 'dropped.v');
      await record('d-kept', inTab.path);
      await record('d-dropped', never.path);
      expect(resolveDesignSourceArtifactPath(env.root, 'd-kept'), inTab.path);
      expect(resolveDesignSourceArtifactPath(env.root, 'd-dropped'), isNull);
    });

    group('request_open_artifact', () {
      test('a design open in a tab is opened', () async {
        final env = await bootApp();
        final file = design(tabDir, 'sibling.v');
        await record('d-tab', file.path);
        final ack = await env.server.ask(
          const RequestOpenArtifact(designId: 'd-tab', artifactKind: 'source'),
        );
        expect(ack.honored, isTrue, reason: ack.reason);
        expect(loaded(env.tab), <String>[file.path]);
      });

      test(
        'a design whose tab was closed — in the recent files — is opened',
        () async {
          final env = await bootApp();
          final file = File(p.join(recentDir.path, 'closed.v'));
          await record('d-closed', file.path);
          final ack = await env.server.ask(
            const RequestOpenArtifact(
              designId: 'd-closed',
              artifactKind: 'source',
            ),
          );
          expect(ack.honored, isTrue, reason: ack.reason);
          expect(loaded(env.tab), <String>[file.path]);
        },
      );

      // The case the route exists for: "Open in NetCrux Desktop" on a design
      // this installation has never seen. It was refused while the route was
      // rooted. The extension publishes the record before it sends, and no
      // hint is sent here, so the record alone has to carry it. MUTATION:
      // restoring the rooted resolution, or the rooted check, in
      // `_resolveOpenArtifact` makes this red.
      test(
        'a design never opened in this installation is honoured under the '
        'floor',
        () async {
          final env = await bootApp();
          final file = design(neverDir, 'never.v');
          await record('d-never', file.path);
          final ack = await env.server.ask(
            const RequestOpenArtifact(
              designId: 'd-never',
              artifactKind: 'source',
            ),
          );
          expect(ack.honored, isTrue, reason: ack.reason);
          expect(loaded(env.tab), <String>[file.path]);
        },
      );
    });

    // The `crux.design_id` fallback keeps the roots: a peer attaches the id to
    // a cross-probe, and the record it selects would be loaded without the
    // user asking for that design. MUTATION, each measured: replacing the
    // rooted rule with the floor (`const CxpPathContainment()`) in
    // `cxpPathContainmentProvider` turns 'never opened' red; dropping the
    // recent lists from `cxpOpenDirectories` turns 'closed tab' red.
    group('the crux.design_id fallback', () {
      Future<RequestHighlightAck> probe(_ScriptedServer server, String id) =>
          server.askHighlight(
            RequestHighlight(
              element: const ElementId(
                kind: ElementKind.signal,
                path: 'top.data',
              ),
              metadata: <String, Object?>{cxpDesignIdMetadataKey: id},
            ),
          );

      test('opens a design in a tab directory', () async {
        final env = await bootApp();
        final file = design(tabDir, 'sibling.v');
        await record('d-tab', file.path);
        final ack = await probe(env.server, 'd-tab');
        expect(ack.honored, isTrue, reason: ack.reason);
        expect(loaded(env.tab), <String>[file.path]);
      });

      test(
        'opens a design whose tab was closed — in the recent files',
        () async {
          final env = await bootApp();
          final file = File(p.join(recentDir.path, 'closed.v'));
          await record('d-closed', file.path);
          final ack = await probe(env.server, 'd-closed');
          expect(ack.honored, isTrue, reason: ack.reason);
          expect(loaded(env.tab), <String>[file.path]);
        },
      );

      test('refuses a design never opened in this installation', () async {
        final env = await bootApp();
        final file = design(neverDir, 'never.v');
        await record('d-never', file.path);
        final ack = await probe(env.server, 'd-never');
        expect(ack.honored, isFalse);
        expect(ack.reason, isNot(contains(file.path)));
        expect(loaded(env.tab), isEmpty);
      });
    });
  });
}

/// CXP on, bound to an ephemeral port so the test never collides with a
/// running NetCrux on the default one.
class _CxpOnEphemeralPort extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings.defaults().copyWith(
    cxpServerEnabled: true,
    cxpServerPort: 0,
  );
}

/// Deletes [dir], tolerating a server that is still removing its manifest
/// from it: the provider stops its server without awaiting the stop.
void _deleteQuietly(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // Best effort.
  }
}

/// A client connected to the server on [port], torn down with the test.
Future<LocalCxpClient> _connect(int port) async {
  final client = LocalCxpClient(
    selfIdentity: const PeerIdentity(
      peerId: 'open-artifact-test',
      productName: 'vscode',
      productVersion: '0.0.0-test',
    ),
  );
  await client.connect(
    host: '127.0.0.1',
    port: port,
    token: cxpProcessAuthToken,
  );
  addTearDown(client.dispose);
  return client;
}

/// A [CxpServer] that delivers exactly the messages a test hands it — no
/// socket, no wire-level screening — and records what the handler sends
/// back.
class _ScriptedServer implements CxpServer {
  final StreamController<InboundCxpMessage> _inbound =
      StreamController<InboundCxpMessage>.broadcast();
  final StreamController<CxpMessage> _sent =
      StreamController<CxpMessage>.broadcast();
  var _nextId = 0;

  static const PeerIdentity _peer = PeerIdentity(
    peerId: 'scripted-peer',
    productName: 'wavecrux',
    productVersion: '0.0.0-test',
  );

  /// Delivers [request] as if [_peer] had sent it and returns the ack.
  Future<RequestOpenArtifactAck> ask(RequestOpenArtifact request) async =>
      await _exchange(
            request,
            (m) => m is RequestOpenArtifactAck ? m.inReplyTo : null,
          )
          as RequestOpenArtifactAck;

  /// Delivers [request] as if [_peer] had sent it and returns the ack.
  Future<RequestHighlightAck> askHighlight(RequestHighlight request) async =>
      await _exchange(
            request,
            (m) => m is RequestHighlightAck ? m.inReplyTo : null,
          )
          as RequestHighlightAck;

  /// Delivers [request] and waits for the message [inReplyTo] reports as
  /// answering it.
  Future<CxpMessage> _exchange(
    CxpMessage request,
    String? Function(CxpMessage message) inReplyTo,
  ) {
    final messageId = 'm${_nextId++}';
    final reply = _sent.stream.firstWhere((m) => inReplyTo(m) == messageId);
    _inbound.add(
      InboundCxpMessage(
        envelope: CxpEnvelope(
          messageId: messageId,
          from: _peer.peerId,
          kind: request.kind,
          payload: request.toJson(),
        ),
        message: request,
        from: _peer,
      ),
    );
    return reply.timeout(const Duration(seconds: 5));
  }

  @override
  Stream<InboundCxpMessage> get inbound => _inbound.stream;

  @override
  bool sendTo(String peerId, CxpMessage message) {
    _sent.add(message);
    return true;
  }

  @override
  PeerIdentity get selfIdentity => const PeerIdentity(
    peerId: 'netcrux-under-test',
    productName: 'netcrux',
    productVersion: '0.0.0-test',
  );

  @override
  int? get boundPort => null;

  @override
  List<PeerIdentity> get connectedPeers => const <PeerIdentity>[_peer];

  @override
  Stream<PeerPresenceEvent> get presence =>
      const Stream<PeerPresenceEvent>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void broadcast(CxpMessage message) {}

  @override
  void attachLinkedPeer(
    PeerIdentity peer,
    void Function(CxpMessage message) send,
  ) {}

  @override
  void detachLinkedPeer(String peerId) {}

  @override
  void injectInbound(InboundCxpMessage message) => _inbound.add(message);
}
