// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart' show CruxCxpRequestHandler;
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netcrux_design_source.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/workspace/providers/recent_lists.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/remote/cxp/cxp_inbound_handler.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../helpers/cxp_runtime_rig.dart';
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
/// deliver the request through [_ScriptedPeer], which hands the handler
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

  Future<void> record(
    String designId,
    String path, {
    String kind = 'source',
  }) => CxpWorkspaceStore(workspaceDirectory: storeDir.path).upsertArtifact(
    designId: designId,
    kind: kind,
    path: path,
    producer: 'peer',
  );

  /// A handler whose rooted rule has [open] as its only root, over a
  /// workspace store that carries that rule — as the production store does.
  /// Nothing on the `request_open_artifact` route should consult either.
  ({_ScriptedPeer server, ProviderContainer tab}) boot({
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
    final handler = NetcruxCxpRequestHandler(
      rootContainer: root,
      activeTabContainerLookup: () => withTab ? tab : null,
    );
    addTearDown(handler.dispose);
    return (server: _ScriptedPeer(handler), tab: tab);
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
      'a kind other than source or project is declined, and nothing is loaded',
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
        expect(ack.reason, contains('only source and project artifacts'));
        expect(loaded(env.tab), isEmpty);
      },
    );

    // A `project` artifact is the hand-off for a multi-file design: a top
    // module that instantiates modules from other files does not elaborate
    // from one `source`, and a project file sent as `source` would have been
    // parsed as HDL. The three project definitions Open Project… and the
    // command line accept are the three this route accepts.
    group('a project artifact', () {
      test('naming a .netcrux-project opens it with its defines, include '
          'paths and top, anchored to its own directory', () async {
        final projectFile = p.join(outside.path, 'soc.netcrux-project');
        await const NetcruxProjectFileWriter().write(
          projectFile,
          NetcruxProject.create(
            sourceFiles: const <String>['rtl/gpio.v', 'rtl/soc_top.v'],
            topModule: 'soc_top',
            defines: const <String, String>{'WIDTH': '32'},
            includePaths: const <String>['inc'],
          ),
        );
        final env = boot();
        final ack = await env.server.ask(
          RequestOpenArtifact(
            designId: 'soc',
            artifactKind: 'project',
            path: projectFile,
          ),
        );
        expect(ack.honored, isTrue, reason: ack.reason);
        final project = env.tab.read(currentProjectProvider);
        expect(project.sourceFiles, <String>[
          p.join(outside.path, 'rtl', 'gpio.v'),
          p.join(outside.path, 'rtl', 'soc_top.v'),
        ]);
        expect(project.topModule, 'soc_top');
        expect(project.defines, const <String, String>{'WIDTH': '32'});
        expect(project.includePaths, <String>[p.join(outside.path, 'inc')]);
        expect(
          env.tab.read(currentProjectProvider.notifier).activeSource,
          NetcruxDesignSource.project,
        );
      });

      test(
        'recorded in the shared workspace is resolved without a hint',
        () async {
          final projectFile = p.join(outside.path, 'alu.netcrux-project');
          await const NetcruxProjectFileWriter().write(
            projectFile,
            NetcruxProject.create(
              sourceFiles: const <String>['alu.v'],
              topModule: 'alu',
            ),
          );
          await record('alu', projectFile, kind: 'project');
          final env = boot();
          final ack = await env.server.ask(
            const RequestOpenArtifact(designId: 'alu', artifactKind: 'project'),
          );
          expect(ack.honored, isTrue, reason: ack.reason);
          expect(loaded(env.tab), <String>[p.join(outside.path, 'alu.v')]);
          expect(env.tab.read(currentProjectProvider).topModule, 'alu');
        },
      );

      test('naming a <design>.crux-project manifest opens its sources and '
          'top', () async {
        for (final f in <String>['defs.vh', 'fifo.v', 'uart_tx.v']) {
          File(p.join(outside.path, 'rtl', f))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('');
        }
        final manifest = File(p.join(outside.path, 'uart.crux-project'))
          ..writeAsStringSync('''
version: 1
name: uart
design:
  top: uart_tx
  sources:
    - rtl/defs.vh
    - rtl/fifo.v
    - rtl/uart_tx.v
''');
        final env = boot();
        final ack = await env.server.ask(
          RequestOpenArtifact(
            designId: 'uart',
            artifactKind: 'project',
            path: manifest.path,
          ),
        );
        expect(ack.honored, isTrue, reason: ack.reason);
        final project = env.tab.read(currentProjectProvider);
        expect(project.sourceFiles.map(p.basename), <String>[
          'defs.vh',
          'fifo.v',
          'uart_tx.v',
        ]);
        expect(project.topModule, 'uart_tx');
      });

      test('naming a .f filelist expands it', () async {
        for (final f in <String>['gpio.v', 'soc_top.v']) {
          File(p.join(outside.path, 'rtl', f))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('');
        }
        final filelist = File(p.join(outside.path, 'soc.f'))
          ..writeAsStringSync('+define+WIDTH=32\nrtl/gpio.v\nrtl/soc_top.v\n');
        final env = boot();
        final ack = await env.server.ask(
          RequestOpenArtifact(
            designId: 'soc',
            artifactKind: 'project',
            path: filelist.path,
          ),
        );
        expect(ack.honored, isTrue, reason: ack.reason);
        final project = env.tab.read(currentProjectProvider);
        expect(project.sourceFiles.map(p.basename), <String>[
          'gpio.v',
          'soc_top.v',
        ]);
        expect(project.defines, const <String, String>{'WIDTH': '32'});
        expect(
          env.tab.read(currentProjectProvider.notifier).activeSource,
          NetcruxDesignSource.filelist,
        );
      });

      test('naming an HDL file is declined, and nothing is loaded', () async {
        final file = design(outside, 'top.v');
        final env = boot();
        final ack = await env.server.ask(
          RequestOpenArtifact(
            designId: 'top',
            artifactKind: 'project',
            path: file.path,
          ),
        );
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('a project artifact must be'));
        expect(ack.reason, isNot(contains(file.path)));
        expect(loaded(env.tab), isEmpty);
      });

      test('naming a project file that does not parse is declined without '
          'repeating the path', () async {
        final broken = File(p.join(outside.path, 'broken.netcrux-project'))
          ..writeAsStringSync('{ not json');
        final env = boot();
        final ack = await env.server.ask(
          RequestOpenArtifact(
            designId: 'broken',
            artifactKind: 'project',
            path: broken.path,
          ),
        );
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('could not be read'));
        expect(ack.reason, isNot(contains(broken.path)));
        expect(loaded(env.tab), isEmpty);
      });

      test('with no record and no hint is declined', () async {
        final env = boot();
        final ack = await env.server.ask(
          const RequestOpenArtifact(
            designId: 'unknown',
            artifactKind: 'project',
          ),
        );
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('no project artifact recorded'));
        expect(loaded(env.tab), isEmpty);
      });
    });

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

    // End to end over a real socket, through the runtime NetCrux's own binding
    // builds: `LocalCxpServer` screens the hint on the wire before the handler
    // sees it, and a rooted screen there strips the hint for a design never
    // opened. No record is written, so the hint is all the handler has.
    // MUTATION: giving `kNetcruxCxpBinding` the rooted
    // `cxpPathContainmentProvider` rule as its containment makes this red.
    test('over a socket, the production server passes a hint for a design '
        'never opened, and it is loaded', () async {
      final file = design(outside, 'never_opened.v');
      final peers = Directory.systemTemp.createTempSync('cxp_artifact_peers_');
      addTearDown(() => _deleteQuietly(peers));
      final root = ProviderContainer(
        overrides: <Override>[
          ...netcruxTelemetryTestOverrides(),
          cxpWorkspaceDirectoryProvider.overrideWithValue(storeDir.path),
          cxpPathContainmentProvider.overrideWithValue(
            CxpPathContainment(roots: () => <String>[open.path]),
          ),
        ],
      );
      addTearDown(root.dispose);
      final host = CxpRuntimeRig(
        manifestDirectory: p.join(peers.path, 'peers'),
      );
      await host.start();
      addTearDown(host.stop);
      final tab = ProviderContainer(parent: root);
      addTearDown(tab.dispose);
      final handler = AttachedCxpHandler(
        server: host,
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
      final server = CxpRuntimeRig(
        manifestDirectory: p.join(peers.path, 'peers'),
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
      final handler = AttachedCxpHandler(
        server: server,
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
      ({_ScriptedPeer server, ProviderContainer root, ProviderContainer tab})
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
      // The Recent lists read the saved settings in the background; the rooted
      // rule sees them once they have.
      await root.read(recentSources.provider.notifier).restored;
      await root.read(recentProjects.provider.notifier).restored;
      await root.read(recentWorkspaces.provider.notifier).restored;
      final tab = ProviderContainer(parent: root);
      addTearDown(tab.dispose);
      final handler = NetcruxCxpRequestHandler(
        rootContainer: root,
        activeTabContainerLookup: () => tab,
      );
      addTearDown(handler.dispose);
      return (server: _ScriptedPeer(handler), root: root, tab: tab);
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
      expect(
        await resolveDesignSourceArtifactPath(env.root, 'd-kept'),
        inTab.path,
      );
      expect(
        await resolveDesignSourceArtifactPath(env.root, 'd-dropped'),
        isNull,
      );
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
      Future<RequestHighlightAck> probe(_ScriptedPeer server, String id) =>
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

/// Calls NetCrux's request handler with exactly the request a test hands it —
/// no socket, no wire-level screening — and wraps what it returns in the
/// acknowledgement the shared runtime would send back.
class _ScriptedPeer {
  _ScriptedPeer(this._handler);

  final CruxCxpRequestHandler _handler;

  static const PeerIdentity _peer = PeerIdentity(
    peerId: 'scripted-peer',
    productName: 'wavecrux',
    productVersion: '0.0.0-test',
  );

  /// Hands [request] to the handler as if [_peer] had sent it and returns the
  /// ack.
  Future<RequestOpenArtifactAck> ask(RequestOpenArtifact request) async {
    final result = await _handler.openArtifact(request, _peer);
    return RequestOpenArtifactAck(
      inReplyTo: 'scripted',
      honored: result.honored,
      reason: result.reason,
    );
  }

  /// Hands [request] to the handler as if [_peer] had sent it and returns the
  /// ack.
  Future<RequestHighlightAck> askHighlight(RequestHighlight request) async {
    final result = await _handler.highlight(request, _peer);
    return RequestHighlightAck(
      inReplyTo: 'scripted',
      honored: result.honored,
      reason: result.reason,
    );
  }
}
