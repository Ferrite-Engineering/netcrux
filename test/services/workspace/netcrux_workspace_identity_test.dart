// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;

import '../../helpers/telemetry_test_overrides.dart';
import '../../helpers/wait_for.dart';

/// Tab identity (`NetcruxWorkspaceCodec.identityOf`) and the dedupe it
/// enables.
///
/// The shipped defect: relaunching NetCrux with a positional project path
/// that the restored workspace already held appended a second tab, once per
/// launch, without bound. Identity is therefore asserted against every path
/// spelling a shell or a restored document can produce, and the dedupe is
/// asserted against a tab rehydrated from disk rather than one opened in the
/// same session — the latter would pass even with raw-string comparison.
void main() {
  const codec = NetcruxWorkspaceCodec();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('netcrux_identity_test_');
  });

  tearDown(() => bestEffortDeleteTempDir(tmp));

  /// Creates [name] under [tmp] and returns its absolute path.
  String touch(String name) {
    final file = File(p.join(tmp.path, name))
      ..createSync(recursive: true)
      ..writeAsStringSync('module m; endmodule\n');
    return file.path;
  }

  NetcruxTabPayload project(String path) =>
      NetcruxTabPayload(sourceFiles: const [], projectFilePath: path);

  NetcruxTabPayload sources(List<String> paths) =>
      NetcruxTabPayload(sourceFiles: paths);

  group('identityOf — project tabs', () {
    test('two payloads for the same project file share one identity', () {
      final path = touch('demo.netcrux-project');
      expect(codec.identityOf(project(path)), codec.identityOf(project(path)));
      expect(codec.identityOf(project(path)), isNotNull);
    });

    test('a relative spelling matches the absolute one', () {
      final absolute = touch('rel.netcrux-project');

      // Identity resolves a relative path against the process working
      // directory, so the spelling has to be relative to *that*. On Windows
      // the system temp dir and the checkout can sit on different volumes,
      // and no relative path spans two volumes — `p.relative` hands back the
      // absolute path instead. Anchor the process at the fixture's directory
      // so a relative spelling exists at all; the identity is what is under
      // test, not where the process happens to be standing.
      final previous = Directory.current;
      Directory.current = tmp;
      addTearDown(() => Directory.current = previous);

      final relative = p.relative(absolute, from: Directory.current.path);
      expect(p.isRelative(relative), isTrue);
      expect(
        codec.identityOf(project(relative)),
        codec.identityOf(project(absolute)),
      );
    });

    test('a trailing separator does not fork the identity', () {
      final path = touch('trail.netcrux-project');
      expect(
        codec.identityOf(project('$path${p.separator}')),
        codec.identityOf(project(path)),
      );
    });

    test('a `..` segment collapses', () {
      final path = touch('dots.netcrux-project');
      final detoured = p.join(
        tmp.path,
        'sub',
        '..',
        p.basename(path),
      );
      expect(
        codec.identityOf(project(detoured)),
        codec.identityOf(project(path)),
      );
    });

    test('a symlink resolves to its target', () {
      final target = touch('linked.netcrux-project');
      final linkPath = p.join(tmp.path, 'alias.netcrux-project');
      Link(linkPath).createSync(target);
      expect(
        codec.identityOf(project(linkPath)),
        codec.identityOf(project(target)),
      );
    });

    test('case differences fold on a case-insensitive filesystem', () {
      final path = touch('Case.netcrux-project');
      final swapped = p.join(tmp.path, 'case.netcrux-project');
      final same =
          codec.identityOf(project(swapped)) == codec.identityOf(project(path));
      // The rule is the platform's, not NetCrux's: folding case on Linux
      // would merge two genuinely different files.
      expect(same, filesystemIsCaseInsensitive);
    });

    test('different project files keep different identities', () {
      expect(
        codec.identityOf(project(touch('a.netcrux-project'))),
        isNot(codec.identityOf(project(touch('b.netcrux-project')))),
      );
    });

    test('view state is not part of the identity', () {
      final path = touch('view.netcrux-project');
      final bare = project(path);
      final dressed = bare.copyWith(
        topModule: 'cpu',
        scopePath: const ['u_cpu', 'alu'],
        expandedScopeKeys: const ['u_cpu'],
        selectionJson: const <String, Object?>{'kind': 'cell'},
        overlayMode: 'fanin',
        zoom: 3.5,
        panX: 120,
        panY: -40,
        sessionExportPath: '/exports/view.netcrux',
      );
      expect(codec.identityOf(dressed), codec.identityOf(bare));
    });
  });

  group('identityOf — source-file tabs', () {
    test('the same file set in a different order is one identity', () {
      final a = touch('a.v');
      final b = touch('b.v');
      final c = touch('c.v');
      expect(
        codec.identityOf(sources([c, a, b])),
        codec.identityOf(sources([a, b, c])),
      );
    });

    test('a duplicated entry does not change the identity', () {
      final a = touch('dup_a.v');
      final b = touch('dup_b.v');
      expect(
        codec.identityOf(sources([a, b, a])),
        codec.identityOf(sources([a, b])),
      );
    });

    test('mixed spellings of the same set collapse', () {
      final a = touch('mix_a.v');
      final b = touch('mix_b.v');
      final relativeA = p.relative(a, from: Directory.current.path);
      final detouredB = p.join(tmp.path, 'sub', '..', p.basename(b));
      expect(
        codec.identityOf(sources([relativeA, detouredB])),
        codec.identityOf(sources([a, b])),
      );
    });

    test('an overlapping but unequal set is deliberately a different tab', () {
      final a = touch('ov_a.v');
      final b = touch('ov_b.v');
      final c = touch('ov_c.v');
      expect(
        codec.identityOf(sources([a, b])),
        isNot(codec.identityOf(sources([a, b, c]))),
      );
      expect(
        codec.identityOf(sources([a, b])),
        isNot(codec.identityOf(sources([a]))),
      );
    });
  });

  group('identityOf — what is deliberately not deduped', () {
    test('a project tab and a source-file tab naming the same file', () {
      final path = touch('same.netcrux-project');
      expect(
        codec.identityOf(project(path)),
        isNot(codec.identityOf(sources([path]))),
      );
    });

    test('an empty payload has no identity', () {
      expect(codec.identityOf(NetcruxTabPayload.empty), isNull);
      expect(codec.identityOf(sources(const [])), isNull);
      expect(codec.identityOf(sources(const ['   '])), isNull);
      expect(
        codec.identityOf(
          const NetcruxTabPayload(sourceFiles: [], projectFilePath: '  '),
        ),
        isNull,
      );
    });

    test('a blank payload keeps its own view state out of the answer', () {
      // A "+" tab the user has panned around in is still an anonymous tab;
      // giving it an identity would make the second blank tab un-openable.
      expect(
        codec.identityOf(
          NetcruxTabPayload.empty.copyWith(zoom: 2, topModule: 'top'),
        ),
        isNull,
      );
    });
  });

  group('openTab dedupe', () {
    late WorkspaceService<NetcruxTabPayload> service;

    // The directory is captured by value, not read from `tmp` at call time.
    // Auto-saves are fire-and-forget, so a save still in flight when the test
    // ends would otherwise land in the *next* test's freshly-created temp
    // directory and be rehydrated there as a phantom tab.
    WorkspaceService<NetcruxTabPayload> makeService() {
      final dir = tmp;
      return WorkspaceService<NetcruxTabPayload>(
        codec: const NetcruxWorkspaceCodec(),
        directoryFactory: () async => dir,
        logger: (_) {},
      );
    }

    ProviderContainer makeContainer(
      WorkspaceService<NetcruxTabPayload> s, {
      Duration debounce = Duration.zero,
    }) {
      return ProviderContainer(
        overrides: [
          ...netcruxTelemetryTestOverrides(),
          netcruxWorkspaceProvider.overrideWith(
            () => NetcruxWorkspaceNotifier(
              service: s,
              autoSaveDebounce: debounce,
            ),
          ),
        ],
      );
    }

    setUp(() {
      service = makeService();
    });

    test('re-opening the same project focuses the existing tab', () async {
      final path = touch('focus.netcrux-project');
      final container = makeContainer(service);
      addTearDown(container.dispose);
      await container.read(netcruxWorkspaceProvider.future);
      final notifier = container.read(netcruxWorkspaceProvider.notifier);

      final first = await notifier.openTab(
        displayName: 'focus',
        payload: project(path),
      );
      final other = await notifier.openTab(
        displayName: 'other',
        payload: project(touch('other.netcrux-project')),
      );
      expect(
        container.read(netcruxWorkspaceProvider).value!.tabs,
        hasLength(2),
      );
      expect(
        container.read(netcruxWorkspaceProvider).value!.activeTabId,
        other,
      );

      final again = await notifier.openTab(
        displayName: 'focus',
        payload: project(path),
      );

      expect(again, first);
      final ws = container.read(netcruxWorkspaceProvider).value!;
      expect(ws.tabs, hasLength(2));
      expect(ws.activeTabId, first);
      await notifier.flushPendingSave();
    });

    test('dedupe: false still opens the deliberate second view', () async {
      final path = touch('twice.netcrux-project');
      final container = makeContainer(service);
      addTearDown(container.dispose);
      await container.read(netcruxWorkspaceProvider.future);
      final notifier = container.read(netcruxWorkspaceProvider.notifier);

      await notifier.openTab(displayName: 'a', payload: project(path));
      await notifier.openTab(
        displayName: 'a',
        payload: project(path),
        dedupe: false,
      );

      expect(
        container.read(netcruxWorkspaceProvider).value!.tabs,
        hasLength(2),
      );
      await notifier.flushPendingSave();
    });

    test(
      'a CLI open dedupes against a tab rehydrated from disk',
      () async {
        // The shipped bug's exact shape: session one persists the tab, the
        // process exits, and launch two hands the path in a different
        // spelling than the one on disk.
        final path = touch('relaunch.netcrux-project');

        final first = makeContainer(service);
        await first.read(netcruxWorkspaceProvider.future);
        await first
            .read(netcruxWorkspaceProvider.notifier)
            .openTab(displayName: 'relaunch', payload: project(path));
        await first.read(netcruxWorkspaceProvider.notifier).flushPendingSave();
        first.dispose();
        expect(File(p.join(tmp.path, 'workspace.json')).existsSync(), isTrue);

        // Relaunch: fresh service, fresh container, fresh notifier.
        final relaunchSpellings = <String>[
          p.relative(path, from: Directory.current.path),
          path,
          p.join(tmp.path, 'sub', '..', p.basename(path)),
        ];
        for (final spelling in relaunchSpellings) {
          final container = makeContainer(makeService());
          final restored = await container.read(
            netcruxWorkspaceProvider.future,
          );
          expect(restored.tabs, hasLength(1));

          await container
              .read(netcruxWorkspaceProvider.notifier)
              .openTab(displayName: 'relaunch', payload: project(spelling));

          expect(
            container.read(netcruxWorkspaceProvider).value!.tabs,
            hasLength(1),
            reason: 'spelling "$spelling" appended a duplicate tab',
          );
          await container
              .read(netcruxWorkspaceProvider.notifier)
              .flushPendingSave();
          container.dispose();
        }
      },
    );

    test(
      'a restored source-file tab dedupes against a reordered CLI open',
      () async {
        final a = touch('cli_a.v');
        final b = touch('cli_b.v');

        final first = makeContainer(service);
        await first.read(netcruxWorkspaceProvider.future);
        await first
            .read(netcruxWorkspaceProvider.notifier)
            .openTab(displayName: 'design', payload: sources([a, b]));
        await first.read(netcruxWorkspaceProvider.notifier).flushPendingSave();
        first.dispose();

        final second = makeContainer(makeService());
        addTearDown(second.dispose);
        await second.read(netcruxWorkspaceProvider.future);
        await second
            .read(netcruxWorkspaceProvider.notifier)
            .openTab(displayName: 'design', payload: sources([b, a]));

        expect(second.read(netcruxWorkspaceProvider).value!.tabs, hasLength(1));
      },
    );

    test('two blank tabs remain independently openable', () async {
      final container = makeContainer(service);
      addTearDown(container.dispose);
      await container.read(netcruxWorkspaceProvider.future);
      final notifier = container.read(netcruxWorkspaceProvider.notifier);

      await notifier.openTab(
        displayName: 'new',
        payload: NetcruxTabPayload.empty,
      );
      await notifier.openTab(
        displayName: 'new',
        payload: NetcruxTabPayload.empty,
      );

      expect(
        container.read(netcruxWorkspaceProvider).value!.tabs,
        hasLength(2),
      );
      await notifier.flushPendingSave();
    });
  });

  group('a URL location is keyed verbatim', () {
    // The web viewer's netlist is a URL. Canonicalizing it as a file path on a
    // desktop build would make it absolute, collapse its dot segments and
    // fold its case, changing what it names. The browser side of the same
    // rule runs in Chrome: netcrux_workspace_codec_web_test.dart.
    test('the same URL is one tab; a different URL is another', () {
      const url = 'https://example.com/n/top.json';
      expect(
        codec.identityOf(const NetcruxTabPayload(sourceFiles: <String>[url])),
        codec.identityOf(
          const NetcruxTabPayload(sourceFiles: <String>[' $url ']),
        ),
      );
      expect(
        codec.identityOf(const NetcruxTabPayload(sourceFiles: <String>[url])),
        isNot(
          codec.identityOf(
            const NetcruxTabPayload(
              sourceFiles: <String>['https://example.com/n/TOP.json'],
            ),
          ),
        ),
      );
    });

    test('a browser upload keeps its blob id and name', () {
      const upload = 'blob:https://app.netcrux.app/5b0c#top.json';
      expect(
        codec.identityOf(
          const NetcruxTabPayload(sourceFiles: <String>[upload]),
        ),
        contains(upload),
      );
    });

    test('a URL keeps its dot segments and query', () {
      const url = 'https://example.com/view?json=a/../b.json';
      expect(
        codec.identityOf(const NetcruxTabPayload(sourceFiles: <String>[url])),
        endsWith(url),
      );
    });
  });
}
