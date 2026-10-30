// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';

void main() {
  late Directory workspaceDir;
  late Directory designDir;
  late File sourceFile;

  setUp(() {
    workspaceDir = Directory.systemTemp.createTempSync('cxp_ws_');
    designDir = Directory.systemTemp.createTempSync('cxp_design_');
    // resolveArtifact prunes entries whose path no longer exists, so the
    // artifact must be a real file on disk.
    sourceFile = File('${designDir.path}/cdc_capture.v')
      ..writeAsStringSync('module top; endmodule');
  });

  tearDown(() {
    workspaceDir.deleteSync(recursive: true);
    designDir.deleteSync(recursive: true);
  });

  ProviderContainer boot() => ProviderContainer(
    overrides: [
      cxpWorkspaceStoreProvider.overrideWithValue(
        CxpWorkspaceStore(workspaceDirectory: workspaceDir.path),
      ),
    ],
  );

  test('cxpDesignIdForProject keys on the source-file directory', () {
    final project = NetcruxProject.create(
      sourceFiles: <String>[sourceFile.path],
    );
    expect(cxpDesignIdForProject(project), cxpDesignIdForPath(sourceFile.path));
    expect(cxpDesignIdForProject(NetcruxProject.empty), isNull);
  });

  test('cxpDesignIdForProject is null where there is no file system', () {
    // What a browser does when asked whether a path is a directory.
    final id = IOOverrides.runZoned(
      () => cxpDesignIdForProject(
        NetcruxProject.create(sourceFiles: const <String>['fixture.json']),
      ),
      fseGetTypeSync: (path, followLinks) =>
          throw UnsupportedError('_Namespace'),
    );
    expect(id, isNull);
  });

  test(
    'publishes source under the source-dir design id (shared-workspace producer)',
    () async {
      final container = boot();
      addTearDown(container.dispose);

      final designId = cxpDesignIdForPath(sourceFile.path);
      await publishDesignSourceArtifact(
        container,
        serverRunning: true,
        designId: designId,
        sourcePath: sourceFile.path,
        topModule: 'top',
      );

      final store = container.read(cxpWorkspaceStoreProvider);
      final resolved = store.resolveArtifact(designId, 'source');
      expect(resolved, isNotNull);
      expect(resolved!.path, sourceFile.path);
      expect(resolved.kind, 'source');
      expect(resolved.producer, 'netcrux');
      expect(resolved.topModule, 'top');
      expect(resolved.basename, 'cdc_capture.v');

      // The shared-workspace consumer resolver finds the same file.
      expect(
        await resolveDesignSourceArtifactPath(container, designId),
        sourceFile.path,
      );
    },
  );

  test(
    "another product's source record for the same design is never opened",
    () async {
      final container = boot();
      addTearDown(container.dispose);

      final designId = cxpDesignIdForPath(sourceFile.path);
      // A lint project and a simulation config, published under the one
      // design id by the products that own them, after NetCrux's own HDL so
      // the store's newest-first fallback would pick one of them.
      final foreign = <File>[
        File('${designDir.path}/rules.lintcrux-project'),
        File('${designDir.path}/bench.simcrux-project'),
      ];
      for (final file in foreign) {
        file.writeAsStringSync('{}');
      }
      await publishDesignSourceArtifact(
        container,
        serverRunning: true,
        designId: designId,
        sourcePath: sourceFile.path,
        topModule: 'top',
      );
      final store = container.read(cxpWorkspaceStoreProvider);
      for (final file in foreign) {
        await store.upsertArtifact(
          designId: designId,
          kind: kCxpSourceArtifactKind,
          path: file.path,
          producer: 'peer',
        );
      }

      expect(
        await resolveDesignSourceArtifactPath(container, designId),
        sourceFile.path,
      );
      expect(
        await resolveOpenArtifactSourcePath(container, designId),
        sourceFile.path,
      );
    },
  );

  test(
    'a design recorded only by other products resolves to nothing',
    () async {
      final container = boot();
      addTearDown(container.dispose);

      final designId = cxpDesignIdForPath(sourceFile.path);
      final foreign = File('${designDir.path}/rules.lintcrux-project')
        ..writeAsStringSync('{}');
      await container
          .read(cxpWorkspaceStoreProvider)
          .upsertArtifact(
            designId: designId,
            kind: kCxpSourceArtifactKind,
            path: foreign.path,
            producer: 'peer',
          );

      expect(
        await resolveDesignSourceArtifactPath(container, designId),
        isNull,
      );
      expect(await resolveOpenArtifactSourcePath(container, designId), isNull);
    },
  );

  test('the accepts filters admit what the open dialogs offer', () {
    for (final path in const [
      '/d/top.v',
      '/d/top.SV',
      '/d/pkg.svh',
      '/d/defs.vh',
      '/d/top.vhd',
      '/d/top.vhdl',
      '/d/top.json',
    ]) {
      expect(netcruxAcceptsSourceArtifact(path), isTrue, reason: path);
    }
    for (final path in const [
      '/d/rules.lintcrux-project',
      '/d/bench.simcrux-project',
      '/d/top.vcd',
      '/d/top.v.bak',
    ]) {
      expect(netcruxAcceptsSourceArtifact(path), isFalse, reason: path);
    }
    for (final path in const [
      '/d/top.netcrux-project',
      '/d/top.crux-project',
      '/d/files.f',
    ]) {
      expect(netcruxAcceptsProjectArtifact(path), isTrue, reason: path);
    }
    expect(netcruxAcceptsProjectArtifact('/d/top.v'), isFalse);
    expect(netcruxAcceptsArtifactOfKind('waveform'), isNull);
  });

  test('is a no-op when the CXP server is not running', () async {
    final container = boot();
    addTearDown(container.dispose);

    final designId = cxpDesignIdForPath(sourceFile.path);
    await publishDesignSourceArtifact(
      container,
      serverRunning: false,
      designId: designId,
      sourcePath: sourceFile.path,
      topModule: 'top',
    );

    expect(
      container.read(cxpWorkspaceStoreProvider).readArtifacts(designId),
      isEmpty,
    );
  });
}
